# Examples and templates

List the templates at any time:

```sh
swiftpico template
```

Create one with `swiftpico init --template NAME`. Every generated program is a
complete `@main` Embedded Swift executable. Replace the generated `main.swift`
after creation; do not edit PicoKit's internal bridge for application behavior.

## Blink

```sh
swiftpico init --board pico --name Blink --template blink
```

For Pico and Pico 2, the generated program drives GPIO 25. For wireless boards,
it uses `BoardLED(board: .picoW)` or `BoardLED(board: .pico2W)`. The template
also announces `Blink started` once each time USB serial connects.

## Serial echo

```sh
swiftpico init --board pico --name SerialEcho --template serial
```

The essential loop is:

```swift
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
```

`Serial.read()` and `Serial.write(_:)` operate on raw bytes. The example does
not translate line endings, making it suitable for byte-level checks as well as
interactive typing.

## ADC

```sh
swiftpico init --board pico --name ADCExample --template adc
```

The generated code creates `PicoADC`, reads GPIO26, and prints the raw value
once per second while USB is connected:

```swift
let adc = try! PicoADC()
while true {
    let raw = try! adc.read(.gpio26)
    if Serial.connected { Serial.println("ADC26: \(raw)") }
    sleep(1_000)
}
```

## PWM

The PWM example creates a 1 kHz controller on GPIO0 and writes a duty value of
128. Replace the constant with a changing value to create a fade or waveform.

```swift
let pin = try! PicoPin(0)
let pwm = try! PicoPWM(pin: pin, frequency: .kilohertz(1))
try! analogWrite(0, UInt8(128), using: pwm)
```

## I2C

The I2C template uses I2C0, SDA GPIO4, SCL GPIO5, 400 kHz, and a 20 ms timeout:

```swift
let i2c = try! PicoI2C(
    .i2c0, frequency: .kilohertz(400),
    sda: try! PicoPin(4), scl: try! PicoPin(5))
let timeout = try! Duration.milliseconds(20)
_ = try? i2c.write(address: 0x50, bytes: [0], timeout: timeout)
```

## SPI

The SPI template configures SPI0 at 40 MHz, mode 0, SCK GPIO18, MOSI GPIO19,
and no MISO pin:

```swift
let spi = try! PicoSPI(
    .spi0, frequency: .megahertz(40),
    sck: .gpio18, mosi: .gpio19, miso: nil, mode: .mode0)
try! spi.write([0x00])
```

## GPIO interrupts

The interrupt template enables a falling-edge event on GPIO17 and polls the
SDK-recorded event count in the foreground:

```swift
let pin = try! PicoPin(17)
let interrupts = PicoInterrupts()
try! interrupts.enable(pin, edge: .falling)
while true {
    if interrupts.takeEvents(for: pin) != 0 {
        // Handle the event outside the interrupt callback.
    }
    sleepMicroseconds(100)
}
```

## Watchdog

The watchdog template enables a five-second timeout and services it once per
second:

```swift
let watchdog = PicoWatchdog()
try! watchdog.enable(timeout: .seconds(5))
while true {
    watchdog.update()
    sleep(1_000)
}
```
