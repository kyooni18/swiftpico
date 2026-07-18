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
                guard let led = try? BoardLED(board: .\(boardCase)) else {
                    halt("LED setup failed")
                }
                var announced = false
                while true {
                    if Serial.connected && !announced {
                        Serial.println("Blink started")
                        announced = true
                    } else if !Serial.connected {
                        announced = false
                    }
                    guard (try? led.set(.high)) != nil else { halt("LED write failed") }
                    sleep(500)
                    guard (try? led.set(.low)) != nil else { halt("LED write failed") }
                    sleep(500)
                }
            }
            @inline(__always) static func halt(_ message: String) -> Never {
                Serial.println(message)
                while true { sleep(1_000) }
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
              var announced = false
              while true {
                  if Serial.connected && !announced {
                      Serial.println("Blink started")
                      announced = true
                  } else if !Serial.connected {
                      announced = false
                  }
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
            var announced = false
            while true {
                if !Serial.connected {
                    announced = false
                    sleep(10)
                } else if !announced {
                    Serial.println("Serial echo ready")
                    announced = true
                } else if let byte = Serial.read() {
                    Serial.write(byte)
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
            guard let adc = try? PicoADC() else { halt("ADC setup failed") }
            while true {
                guard let raw = try? adc.read(.gpio26) else { halt("ADC read failed") }
                if Serial.connected {
                    Serial.println("ADC26: \\(raw)")
                }
                sleep(1_000)
            }
        }
        @inline(__always) static func halt(_ message: String) -> Never {
            Serial.println(message)
            while true { sleep(1_000) }
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
            guard let pin = try? PicoPin(0),
                let pwm = try? PicoPWM(pin: pin, frequency: .kilohertz(1)) else {
                halt("PWM setup failed")
            }
            while true {
                guard (try? analogWrite(0, UInt8(128), using: pwm)) != nil else {
                    halt("PWM write failed")
                }
                sleep(10)
            }
        }
        @inline(__always) static func halt(_ message: String) -> Never {
            Serial.println(message)
            while true { sleep(1_000) }
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
            guard let sda = try? PicoPin(4), let scl = try? PicoPin(5),
                let i2c = try? PicoI2C(.i2c0, frequency: .kilohertz(400), sda: sda, scl: scl),
                let timeout = try? Duration.milliseconds(20) else {
                halt("I2C setup failed")
            }
            while true {
                if (try? i2c.write(address: 0x50, bytes: [0], timeout: timeout)) == nil {
                    Serial.println("I2C write failed; retrying")
                }
                sleep(1_000)
            }
        }
        @inline(__always) static func halt(_ message: String) -> Never {
            Serial.println(message)
            while true { sleep(1_000) }
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
            guard let spi = try? PicoSPI(
                .spi0,
                frequency: .megahertz(40),
                sck: .gpio18,
                mosi: .gpio19,
                miso: nil,
                mode: .mode0
            )
            else { halt("SPI setup failed") }
            guard (try? spi.write([UInt8(0x00)])) != nil else { halt("SPI write failed") }
            while true { sleep(1_000) }
        }
        @inline(__always) static func halt(_ message: String) -> Never {
            Serial.println(message)
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
            guard let pin = try? PicoPin(17) else { halt("interrupt pin setup failed") }
            let interrupts = PicoInterrupts()
            guard (try? interrupts.enable(pin, edge: .falling)) != nil else {
                halt("interrupt setup failed")
            }
            while true {
                if interrupts.takeEvents(for: pin) != 0 { /* handle in foreground */ }
                sleepMicroseconds(100)
            }
        }
        @inline(__always) static func halt(_ message: String) -> Never {
            Serial.println(message)
            while true { sleep(1_000) }
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
            guard (try? watchdog.enable(timeout: .seconds(5))) != nil else {
                Serial.println("watchdog setup failed")
                while true { sleep(1_000) }
            }
            while true {
                watchdog.update()
                sleep(1_000)
            }
        }
    }
    """
  }
}
