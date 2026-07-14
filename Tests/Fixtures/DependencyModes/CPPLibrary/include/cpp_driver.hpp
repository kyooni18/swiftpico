#pragma once
#include <stdint.h>
class MockDisplayDriver {
public:
    explicit MockDisplayDriver(uint32_t identifier) : identifier_(identifier) {}
    uint32_t identifier() const { return identifier_; }
private:
    uint32_t identifier_;
};
