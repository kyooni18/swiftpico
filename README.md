# SwiftPico

SwiftPico is the command-line companion to [PicoKit](https://github.com/kyooni18/PicoKit). It creates Pico firmware projects, builds them with Embedded Swift, flashes them over USB, and provides an interactive serial terminal.

## Install with Homebrew

```sh
brew tap kyooni18/swiftpico https://github.com/kyooni18/swiftpico
brew install swiftpico
```

The formula installs `picotool` as well, which lets `swiftpico flash` move a UF2 onto a running Pico over USB without holding BOOTSEL or physically reconnecting the board.

## Create a project

```sh
swiftpico init --board pico2_w --name Blink --template blink
cd Blink
swiftpico build
swiftpico flash
swiftpico monitor --reconnect
```

`monitor` forwards typed bytes to the board while displaying its USB CDC output.
It keeps Ctrl-C for leaving the terminal and restores the local terminal mode on
exit.

The `serial` template is an exact byte echo using `Serial.read()` and raw-byte
`Serial.write(_:)`, making it useful for both interactive bring-up and the
automated USB hardware gate.

`init` creates a standalone Swift package with the latest stable PicoKit tag, a board-specific `swiftpico.json`, a firmware CMake entrypoint, and a local `swiftpico` launcher. Add `--pico-kit-version VERSION` when you need a different PicoKit release, or `--skip-resolve` for an offline scaffold. Use `--pico-kit-path /path/to/PicoKit` to develop against a local checkout before a PicoKit change is released as a tag.

Generated firmware enables the Pico SDK USB stdio reset interface and disables UART stdio:

```cmake
pico_enable_stdio_usb(your_target 1)
pico_enable_stdio_uart(your_target 0)
```

## Flashing

The normal flash path uses the USB interface directly:

```sh
swiftpico flash
```

SwiftPico runs `picotool load -f` when available, which asks compatible USB-stdio firmware to reboot into the bootloader, loads the UF2, and returns to the application. If `picotool` is unavailable or cannot reset the board, SwiftPico uses the USB CDC 1200-baud reset exposed by the same USB stdio setting, waits for BOOTSEL storage, and copies the UF2. If you already mounted a BOOTSEL volume, the explicit compatibility path remains available:

```sh
swiftpico flash --volume /Volumes/RPI-RP2
```

If the firmware does not expose picotool's vendor reset interface, SwiftPico
falls back to the Pico SDK's USB CDC 1200-baud reset and copies the UF2 to the
BOOTSEL volume after it mounts. This still requires no BOOTSEL button press.

## External libraries

Current PicoKit firmware builds automatically load `Firmware/Dependencies.cmake`.
SwiftPico's `add` command writes that file and, for Swift packages, updates the
generated `Package.swift` too.

Add a Foundation-free Embedded Swift package target:

```sh
swiftpico add swift \
  --url https://github.com/example/EmbeddedMath.git \
  --from 1.0.0 --package EmbeddedMath --product EmbeddedMath
```

Then import it normally in `Sources/<App>/main.swift`:

```swift
import PicoKit
import EmbeddedMath
```

Add a C or C++ library that exports a Pico-compatible CMake target:

```sh
swiftpico add c \
  --url https://github.com/example/tiny-driver.git \
  --tag v1.2.0 --target tiny_driver
```

The generated `Firmware/Dependencies.cmake` remains ordinary CMake, so it is
easy to adjust a source directory, add include paths, or link other CMake
targets. A library must support the Pico cross compiler; for Swift, it must
also be Foundation-free and compatible with Embedded Swift.

## Development

```sh
swift build
swift run swiftpico help
sh Tests/cli-integration.sh
PICOKIT_TEST_ROOT=../PicoKit sh Tests/firmware-matrix.sh
```

The CLI integration suite generates every template and checks local PicoKit and
fake-picotool paths. The firmware matrix compiles all boards plus serial echo on
both RP2040 and RP2350 against the explicit local PicoKit checkout.
