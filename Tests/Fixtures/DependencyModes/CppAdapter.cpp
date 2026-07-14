#include "cpp_driver.hpp"
extern "C" uint32_t cpp_adapter_identifier(void) {
    return MockDisplayDriver(9341).identifier();
}
