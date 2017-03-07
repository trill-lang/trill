//
//  arc.h
//  trill
//
//  Created by Harlan Haskins on 3/6/17.
//  Copyright © 2017 Harlan. All rights reserved.
//

#ifndef arc_h
#define arc_h

#include "defines.h"
#include <stdint.h>
#include <stdio.h>

#ifdef __cplusplus
namespace trill {
extern "C" {
#endif

/**
 A deinitializer function that tears down an indirect type.
 */
typedef void (*_Nullable trill_deinitializer_t)(void *_Nonnull);

/**
 Creates a heap-allocated, reference-counted box that holds the retain count
 for an indirect type.

 @param size The indirect type's size.
 @param deinit (optional) A pointer to the deinitializer for this indirect type.
 @return A pointer to the top of the raw payload of the indirect type, which
         can be cast to the Trill type.
 */
void *_Nonnull trill_allocateIndirectType(size_t size,
                                          trill_deinitializer_t deinit);

/**
 Performs a thread-safe retain operation that increases the retain count of an
 indirect type.

 @param instance A pointer to an indirect type.
 */
void trill_retain(void *_Nonnull instance);

/**
 Performs a thread-safe release operation that decreases the retain count of an
 indirect type.

 @param instance A pointer to an indirect type.
 @note If the retain count becomes zero as a result of this operation, then the
       indirect type will be deallocated, its deinitializer will be called,
       and this instance will be invalidated.
 */
void trill_release(void *_Nonnull instance);

/**
 Determines if an indirect type instance is uniquely referenced. This is used
 to implement Copy-on-Write.
 
 @param instance A pointer to an indirect type.
 @return True if the instance's retain count is exactly one,
         otherwise returns false.
 */
bool trill_isUniquelyReferenced(void *_Nonnull instance);

#ifdef __cplusplus
} // end extern "C"
} // end namespace trill
#endif

#endif /* arc_hpp */
