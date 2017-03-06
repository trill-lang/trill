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

using namespace trill;

/**
 A RAII class that will lock a mutex when it's constructed
 and unlock the mutex once it's destroyed.
 */
struct LockRAII {
  pthread_mutex_t mutex;

  /**
   Locks the provided mutex
   */
  LockRAII(pthread_mutex_t mutex): mutex(mutex) {
    pthread_mutex_lock(&mutex);
  }

  /**
   Unlocks the provided mutex
   */
  ~LockRAII() {
    pthread_mutex_unlock(&mutex);
  }
};

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
  pthread_mutex_t mutex;

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
   */
  static RefCountBox *createBox(size_t size) {
    auto boxPtr = trill_alloc(sizeof(RefCountBox) + size);
    auto box = reinterpret_cast<RefCountBox *>(boxPtr);
    box->retainCount = 0;
    pthread_mutex_init(&box->mutex, nullptr);
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

  uint32_t retainCount() {
    auto locker = LockRAII(box->mutex);
    return box->retainCount;
  }

  /**
   Retains the value inside a RefCountBox.
   */
  void retain() {
    auto locker = LockRAII(box->mutex);
    if (box->retainCount == UINT32_MAX) {
      trill_fatalError("attempting to retain object with retain count UINT32_MAX");
    }
    box->retainCount++;
  }

  /**
   Releases the value inside a RefCountBox.
   */
  void release() {
    auto locker = LockRAII(box->mutex);
    if (box->retainCount == 0) {
      trill_fatalError("attempting to release object with retain count 0");
    }
    box->retainCount--;
    if (box->retainCount == 0) {
      dealloc();
    }
  }

  /**
   Deallocates the value inside a RefCountBox.
   */
  void dealloc() {
    pthread_mutex_lock(&box->mutex);
    if (box->retainCount > 0) {
      trill_fatalError("object deallocated with retain count > 0");
    }
    free(box->value());
    pthread_mutex_unlock(&box->mutex);
    pthread_mutex_destroy(&box->mutex);
  }
};

void *_Nonnull trill_allocateIndirectType(size_t size) {
  return RefCounted::createBox(size)->value();
}

void trill_retain(void *_Nonnull instance) {
  auto refCounted = RefCounted(instance);
  refCounted.retain();
}

void trill_release(void *_Nonnull instance) {
  auto refCounted = RefCounted(instance);
  refCounted.release();
}
