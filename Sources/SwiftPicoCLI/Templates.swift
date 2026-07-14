extension SwiftPicoCommand {
    static let availableTemplates: Set<String> = [
        "blink", "serial", "adc", "pwm", "i2c", "spi", "interrupt", "watchdog",
    ]

    static func showTemplates(_ arguments: [String]) {
        print("Available templates:")
        print("  blink         — Toggle onboard LED")
        print("  serial        — USB CDC serial echo")
        print("  adc           — Read ADC GPIO26")
        print("  pwm           — Set a PWM duty cycle")
        print("  i2c           — I2C timeout-safe write example")
        print("  spi           — Configure SPI bus")
        print("  interrupt     — Poll SDK-recorded GPIO edge events")
        print("  watchdog      — Enable and service watchdog")
    }

    static func templateSource(template: String, board: String, name: String) -> String {
        switch template {
        case "blink": embeddedBlinkTemplate(board: board)
        case "serial": embeddedSerialTemplate()
        case "adc": adcTemplate()
        case "pwm": pwmTemplate()
        case "i2c": i2cTemplate()
        case "spi": spiTemplate()
        case "interrupt": interruptTemplate()
        case "watchdog": watchdogTemplate()
        default: embeddedBlinkTemplate(board: board)
        }
    }

    private static func embeddedBlinkTemplate(board: String) -> String {
        if board == "pico_w" || board == "pico2_w" {
            let boardCase = board == "pico_w" ? "picoW" : "pico2W"
            return """
            import PicoKit

            @main
            struct Blink {
                static func main() {
                    let led = try! BoardLED(board: .\(boardCase))
                    Serial.println("Blink started")
                    while true {
                        try! led.set(.high)
                        sleep(500)
                        try! led.set(.low)
                        sleep(500)
                    }
                }
            }
            """
        }

        return """
        import PicoKit

        @main
        struct Blink {
            static func main() {
                pinMode(25, .output)
                Serial.println("Blink started")
                while true {
                    digitalWrite(25, .high)
                    sleep(500)
                    digitalWrite(25, .low)
                    sleep(500)
                }
            }
        }
        """
    }

    private static func embeddedSerialTemplate() -> String {
        """
        import PicoKit

        @main
        struct SerialEcho {
            static func main() {
                while true {
                    if let byte = Serial.read() {
                        Serial.write([byte])
                    } else {
                        sleepMicroseconds(100)
                    }
                }
            }
        }
        """
    }

    private static func adcTemplate() -> String {
        """
        import PicoKit

        @main
        struct ADCExample {
            static func main() {
                let adc = try! PicoADC()
                while true {
                    let raw = try! adc.read(.gpio26)
                    Serial.println("ADC26: \\(raw)")
                    sleep(1_000)
                }
            }
        }
        """
    }

    private static func pwmTemplate() -> String {
        """
        import PicoKit

        @main
        struct PWMExample {
            static func main() {
                let pin = try! PicoPin(0)
                let pwm = try! PicoPWM(pin: pin, frequency: .kilohertz(1))
                while true {
                    try! analogWrite(0, 128, using: pwm)
                    sleep(10)
                }
            }
        }
        """
    }

    private static func i2cTemplate() -> String {
        """
        import PicoKit

        @main
        struct I2CExample {
            static func main() {
                let i2c = try! PicoI2C(.i2c0, frequency: .kilohertz(400), sda: try! PicoPin(4), scl: try! PicoPin(5))
                let timeout = try! Duration.milliseconds(20)
                while true {
                    _ = try? i2c.write(address: 0x50, bytes: [0], timeout: timeout)
                    sleep(1_000)
                }
            }
        }
        """
    }

    private static func spiTemplate() -> String {
        """
        import PicoKit

        @main
        struct SPIExample {
            static func main() {
                let spi = try! PicoSPI(
                    .spi0,
                    frequency: .megahertz(40),
                    sck: .gpio18,
                    mosi: .gpio19,
                    miso: nil,
                    mode: .mode0
                )
                try! spi.write([0x00])
                while true { sleep(1_000) }
            }
        }
        """
    }

    private static func interruptTemplate() -> String {
        """
        import PicoKit

        @main
        struct InterruptExample {
            static func main() {
                let pin = try! PicoPin(17)
                let interrupts = PicoInterrupts()
                try! interrupts.enable(pin, edge: .falling)
                while true {
                    if interrupts.takeEvents(for: pin) != 0 { /* handle in foreground */ }
                    sleepMicroseconds(100)
                }
            }
        }
        """
    }

    private static func watchdogTemplate() -> String {
        """
        import PicoKit

        @main
        struct WatchdogExample {
            static func main() {
                let watchdog = PicoWatchdog()
                try! watchdog.enable(timeout: .seconds(5))
                while true {
                    watchdog.update()
                    sleep(1_000)
                }
            }
        }
        """
    }
}
