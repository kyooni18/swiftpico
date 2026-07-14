#include "AppInterop.h"
#include "st7789.h"

void app_st7789_configure(
    uint16_t dc,
    uint16_t cs,
    int16_t reset,
    uint16_t sck,
    uint16_t mosi
) {
    LCD_setPins(dc, cs, reset, sck, mosi);
    LCD_setSPIperiph(spi0);
}
