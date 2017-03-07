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

using namespace trill;

/**
 A RefCountBox contains
  - A retain count
  - A mutex used to synchronize retains and releases
  - A variably-sized payload that is not represented by a data member.

  It is meant as a hidden store for retain count data alongside the allocated
  contents of an indirect type.

  Trill will always see this as:
      [retainCount][mutex][payload]
                          ^~ indirect type "begins" here
 */
struct RefCountBox {
  uint32_t retainCount;
  trill_deinitializer_t deinit;
  std::mutex mutex;

  /// Finds the payload by walking to the end of the data members of this box.
  void *value() {
    return reinterpret_cast<void *>(reinterpret_cast<uintptr_t>(this) +
                                    sizeof(RefCountBox));
  }
};

/**
 A convenience struct that performs the arithmetic necessary to work with a
 \c RefCountBox.
 */
struct RefCounted {
public:
  RefCountBox *box;

  /**
   Creates a \c RefCountBox along with a payload of the specific size.
   @param size The size of the underlying payload.
   @param deinit The deinitializer for the type being created.
   */
  static RefCountBox *createBox(size_t size, trill_deinitializer_t deinit) {
    auto boxPtr = trill_alloc(sizeof(RefCountBox) + size);
    auto box = reinterpret_cast<RefCountBox *>(boxPtr);
    box->retainCount = 1;
    box->deinit = deinit;
    std::cout << "allocated new retained object with retain count " << box->retainCount
              << "and deinitializer " << deinit << std::endl;
    return box;
  }

  /**
   Gets a \c RefCounted instance for a given pointer into a box, by offsetting
   the value pointer with the size of the \c RefCountBox.
   
   @param boxValue The payload value underlying a \c RefCountBox.
   */
  RefCounted(void *_Nonnull boxValue) {
    auto boxPtr = reinterpret_cast<uintptr_t>(boxValue) - sizeof(RefCountBox);
    box = reinterpret_cast<RefCountBox *>(boxPtr);
  }

  /**
   Gets the current retain count of an object.
   */
  uint32_t retainCount() {
    std::lock_guard<std::mutex> guard(box->mutex);
    return box->retainCount;
  }

  /**
   Retains the value inside a \c RefCountBox.
   */
  void retain() {
    std::lock_guard<std::mutex> guard(box->mutex);
    if (box->retainCount == std::numeric_limits<decltype(box->retainCount)>::max()) {
      trill_fatalError("retain count overflow");
    }
    box->retainCount++;
  }

  /**
   Releases the value inside a \c RefCountBox.
   */
  void release() {
    std::lock_guard<std::mutex> guard(box->mutex);
    if (box->retainCount == 0) {
      trill_fatalError("attempting to release object with retain count 0");
    }
    box->retainCount--;
    if (box->retainCount == 0) {
      dealloc();
    }
  }

  /**
   Deallocates the value inside a \c RefCountBox.
   */
  void dealloc() {
    std::lock_guard<std::mutex> guard(box->mutex);
    if (box->retainCount > 0) {
      trill_fatalError("object deallocated with retain count > 0");
    }
    if (box->deinit != nullptr) {
      box->deinit(box->value());
    }
    free(box->value());
  }

  bool isUniquelyReferenced() {
    std::lock_guard<std::mutex> guard(box->mutex);
    return box->retainCount == 1;
  }
};

void *_Nonnull trill_allocateIndirectType(size_t size,
                                          trill_deinitializer_t deinit) {
  return RefCounted::createBox(size, deinit)->value();
}

void trill_retain(void *_Nonnull instance) {
  auto refCounted = RefCounted(instance);
  refCounted.retain();
}

void trill_release(void *_Nonnull instance) {
  auto refCounted = RefCounted(instance);
  refCounted.release();
}

bool trill_isUniquelyReferenced(void *_Nonnull instance) {
  auto refCounted = RefCounted(instance);
  return refCounted.isUniquelyReferenced();
}
