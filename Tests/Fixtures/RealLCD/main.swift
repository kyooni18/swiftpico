import PicoKit

@main
struct RealLCD {
    static func main() {
        // Compile and link the driver through an application-owned adapter.
        // Hardware initialization is intentionally left to the physical test.
        app_st7789_configure(16, 17, -1, 18, 19)
        while true { sleep(1_000) }
    }
}
