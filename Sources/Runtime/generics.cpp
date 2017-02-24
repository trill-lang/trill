#include "generics.h"
#include "trill.h"
#include "metadata_private.h"

using namespace trill;

void *trill_createGenericBox(void *typeMetadata, void *witnessTable) {
    trill_assert(typeMetadata != nullptr);
    trill_assert(witnessTable != nullptr);
    auto metadata = (TypeMetadata *)typeMetadata;
    auto fullSize = sizeof(GenericBox) + metadata->sizeInBits;
    auto box = (GenericBox *)trill_alloc(fullSize);
    trill_assert(box != nullptr);
    box->typeMetadata = metadata;
    box->witnessTable = witnessTable;
    return box;
}

void *trill_genericBoxValuePtr(void *box) {
    trill_assert(box != nullptr);
    return ((intptr_t *)box) + sizeof(GenericBox);
}
