#include "AppInterop.h"
#include "header_only.h"
#include "local_only.h"
#include "archive_only.h"
uint32_t header_adapter_value(void) { return header_only_value(); }
uint32_t local_adapter_value(void) { return local_only_value(); }
uint32_t archive_adapter_value(void) { return archive_only_value(); }
