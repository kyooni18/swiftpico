#include "MockLCD.h"
uint32_t mock_lcd_checksum(const uint8_t *bytes, uint32_t count) {
    uint32_t result = 0;
    for (uint32_t index = 0; index < count; ++index) result += bytes[index];
    return result;
}
