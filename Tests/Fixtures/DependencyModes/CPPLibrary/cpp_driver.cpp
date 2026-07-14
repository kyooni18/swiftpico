#include "cpp_driver.hpp"
uint32_t cpp_driver_translation_unit_anchor(void) {
    return MockDisplayDriver(9341).identifier();
}
