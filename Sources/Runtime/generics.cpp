#include "generics.h"
#include "trill.h"
#include "metadata_private.h"

using namespace trill;

void *trill_createGenericBox(const void *typeMetadata, const void **witnessTable) {
    trill_assert(typeMetadata != nullptr);
    trill_assert(witnessTable != nullptr);
    auto metadata = reinterpret_cast<const TypeMetadata *>(typeMetadata);
    auto fullSize = sizeof(GenericBox) + metadata->sizeInBits;
    auto box = reinterpret_cast<GenericBox *>(trill_alloc(fullSize));
    trill_assert(box != nullptr);
    box->typeMetadata = metadata;
    box->witnessTable = witnessTable;
    return box;
}

void *trill_genericBoxValuePtr(void *box) {
    trill_assert(box != nullptr);
    return reinterpret_cast<intptr_t *>(box) + sizeof(GenericBox);
}
