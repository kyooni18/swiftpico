#pragma once

#include <stdint.h>

void app_st7789_configure(
    uint16_t dc,
    uint16_t cs,
    int16_t reset,
    uint16_t sck,
    uint16_t mosi
);
