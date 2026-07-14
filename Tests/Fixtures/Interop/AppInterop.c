#include "AppInterop.h"
int32_t app_invoke_callback(uint32_t byte_count) {
    return app_frame_ready(byte_count);
}
