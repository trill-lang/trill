//
//  arc.cpp
//  trill
//
//  Created by Harlan Haskins on 3/6/17.
//  Copyright © 2017 Harlan. All rights reserved.
//

#include "arc.h"
#include "trill.h"
#include <cstdlib>
#include <atomic>
#include <mutex>
#include <iostream>
#include <sstream>
#include <chrono>

// #define DEBUG_ARC

#ifdef DEBUG_ARC
#define DEBUG_ARC_LOG(x) do { \
   std::cout << x << " (" << value \
             << ") -- retain count is now " << box->retainCount << std::endl; \
} while (false)
#else
#define DEBUG_ARC_LOG(x) ({})
#endif

#ifdef DEBUG_ARC
#define CHECK_VALID_BOX() do {                    \
  if (box->deallocated) {                         \
    std::cout << "object (" << value              \
              << ") accessed after deallocation"  \
              << std::endl;                       \
  }                                               \
} while (false)
#else
#define CHECK_VALID_BOX() ({})
#endif

namespace trill {

/**
 A RefCountBox contains
  - An atomic retain count
  - A pointer to the type's deinitializer
  - A variably-sized payload that is not represented by a data member.

  It is meant as a hidden store for retain count data alongside the allocated
  contents of an indirect type.

  Trill will always see this as:
      [box reference (RefCountBox *)][payload (void *)]
                                     ^~ indirect type "begins" here
 */
struct RefCountBox {
#ifdef DEBUG_ARC
  bool deallocated;
#endif
  std::atomic<uint32_t> retainCount;
  trill_deinitializer_t deinit;

  RefCountBox(uint32_t retainCount, trill_deinitializer_t deinit):
    retainCount(retainCount), deinit(deinit) {}
};

/**
 A convenience struct that performs the arithmetic necessary to work with a
 \c RefCountBox.
 */
struct RefCounted {
public:
  RefCountBox *box;
  void *value;

  /**
   Creates a \c RefCounted along with a payload of the specific size.
   @param size The size of the underlying payload.
   @param deinit The deinitializer for the type being created.
   */
  RefCounted(size_t size, trill_deinitializer_t deinit) {
    auto boxPtr = trill_alloc(sizeof(RefCountBox) + size);
    new (boxPtr) RefCountBox(0, deinit);
    box = reinterpret_cast<RefCountBox *>(boxPtr);
    value = reinterpret_cast<void *>(
              reinterpret_cast<uintptr_t>(boxPtr) + sizeof(RefCountBox));
    DEBUG_ARC_LOG("creating box");
  }

  /**
   Gets a \c RefCounted instance for a given pointer into a box, by offsetting
   the value pointer with the size of the \c RefCountBox.
   
   @param boxedValue The payload value underlying a \c RefCountBox.
   */
  RefCounted(void *_Nonnull boxedValue) {
    value = boxedValue;
    box = reinterpret_cast<RefCountBox *>(
            reinterpret_cast<uintptr_t>(value) - sizeof(RefCountBox));;
  }

  /**
   Determines if this object's reference count is exactly one.
   */
  bool isUniquelyReferenced() {
    CHECK_VALID_BOX();
    return box->retainCount == 1;
  }

  /**
   Gets the current retain count of an object.
   */
  uint32_t retainCount() {
    CHECK_VALID_BOX();
    DEBUG_ARC_LOG("getting retain count");
    return box->retainCount;
  }

  /**
   Retains the value inside a \c RefCountBox.
   */
  void retain() {
    CHECK_VALID_BOX();
    auto prev = box->retainCount.fetch_add(1);
    DEBUG_ARC_LOG("retaining object");
    if (prev == std::numeric_limits<uint32_t>::max()) {
      std::stringstream msg;
      msg << "retain count overflowed for " << value;
      trill_fatalError(msg.str().c_str());
    }
  }

  /**
   Releases the value inside a \c RefCountBox. If the value hits zero when
   this method is called, then the object will be explicitly deallocated.
   */
  void release() {
    CHECK_VALID_BOX();
    uint32_t prev = box->retainCount.fetch_sub(1);

    if (prev == 1) {
      dealloc();
    } else if (prev == std::numeric_limits<uint32_t>::min()) {
      std::stringstream msg;
      msg << "retain count underflowed for " << value;
      trill_fatalError(msg.str().c_str());
    }

    DEBUG_ARC_LOG("releasing object");

  }

private:
  /**
   Deallocates the value inside a \c RefCountBox.
   @note This function *must* be called with a locked \c mutex.
   */
  void dealloc() {
    CHECK_VALID_BOX();
    if (box->retainCount > 0) {
      trill_fatalError("object deallocated with retain count > 0");
    }

    DEBUG_ARC_LOG("deallocating");

    if (box->deinit != nullptr) {
      box->deinit(value);
    }

#ifdef DEBUG_ARC
    box->deallocated = true;
#else
    free(box);
#endif
  }
};

void *_Nonnull trill_allocateIndirectType(size_t size,
                                          trill_deinitializer_t deinit) {
  return RefCounted(size, deinit).value;
}

void trill_retain(void *_Nonnull instance) {
  auto refCounted = RefCounted(instance);
  refCounted.retain();
}

void trill_release(void *_Nonnull instance) {
  auto refCounted = RefCounted(instance);
  refCounted.release();
}

uint8_t trill_isUniquelyReferenced(void *_Nonnull instance) {
  auto refCounted = RefCounted(instance);
  return refCounted.isUniquelyReferenced() ? 1 : 0;
}

}
