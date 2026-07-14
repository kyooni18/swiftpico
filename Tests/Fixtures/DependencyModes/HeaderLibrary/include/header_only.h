#pragma once
#include <stdint.h>
#include "header_fixture_config.h"
#ifndef HEADER_FIXTURE_ENABLED
#error "HEADER_FIXTURE_ENABLED must be propagated to header-only dependencies"
#endif
static inline uint32_t header_only_value(void) { return HEADER_FIXTURE_VALUE; }
