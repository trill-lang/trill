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

namespace trill {

/**
 A RefCountBox contains
  - A retain count
  - A pointer to the type's deinitializer
  - A mutex used to synchronize retains and releases
  - A variably-sized payload that is not represented by a data member.

  It is meant as a hidden store for retain count data alongside the allocated
  contents of an indirect type.

  Trill will always see this as:
      [retainCount][mutex][deinitializer][payload]
                                         ^~ indirect type "begins" here
 */
struct RefCountBox {
  uint32_t retainCount;
  trill_deinitializer_t deinit;

  // TODO: Figure out how to avoid heap-allocating this mutex.
  std::mutex *mutex;

  RefCountBox(uint32_t retainCount, trill_deinitializer_t deinit):
    retainCount(retainCount), deinit(deinit) {
      this->mutex = new std::mutex();
  }

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
    *box = RefCountBox(1, deinit);
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
   Determines if this object's reference count is exactly one.
   */
  bool isUniquelyReferenced() {
    trill_assert(box != nullptr);
    std::lock_guard<std::mutex> guard(*box->mutex);
    return box->retainCount == 1;
  }

  /**
   Gets the current retain count of an object.
   */
  uint32_t retainCount() {
    trill_assert(box != nullptr);
    std::lock_guard<std::mutex> guard(*box->mutex);
    return box->retainCount;
  }

  /**
   Retains the value inside a \c RefCountBox.
   */
  void retain() {
    trill_assert(box != nullptr);
    std::lock_guard<std::mutex> guard(*box->mutex);
    if (box->retainCount == std::numeric_limits<decltype(box->retainCount)>::max()) {
      trill_fatalError("retain count overflow");
    }
    box->retainCount++;
  }

  /**
   Releases the value inside a \c RefCountBox. If the value hits zero when
   this method is called, then the object will be explicitly deallocated.
   */
  void release() {
    trill_assert(box != nullptr);
    box->mutex->lock();
    if (box->retainCount == 0) {
      trill_fatalError("attempting to release object with retain count 0");
    }
    box->retainCount--;

    if (box->retainCount == 0) {
      dealloc(); // will unlock and invalidate the mutex.
    } else {
      // if we did not deallocate, we need to explicitly unlock the mutex.
      box->mutex->unlock();
    }
  }

private:
  /**
   Deallocates the value inside a \c RefCountBox.
   @note This function *must* be called with a locked \c mutex.
         The mutex will be explicitly unlocked when this function runs,
         and will be invalidated.
   */
  void dealloc() {
    trill_assert(box != nullptr);

    if (box->retainCount > 0) {
      trill_fatalError("object deallocated with retain count > 0");
    }

    if (box->deinit != nullptr) {
      box->deinit(box->value());
    }

    box->mutex->unlock();

    delete box->mutex;

    // Cannot delete the box because it was allocated manually.
    free(box);
    box = nullptr;
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

uint8_t trill_isUniquelyReferenced(void *_Nonnull instance) {
  auto refCounted = RefCounted(instance);
  return refCounted.isUniquelyReferenced() ? 1 : 0;
}

}
