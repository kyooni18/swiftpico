# Beginner's guide

This guide assumes macOS 13 or newer and a Raspberry Pi Pico, Pico W, Pico 2,
or Pico 2 W connected with a data-capable USB cable.

## 1. Install the toolchain

Install SwiftPico with Homebrew:

```sh
brew tap kyooni18/swiftpico https://github.com/kyooni18/swiftpico
brew install swiftpico
```

The formula also installs `picotool`. Firmware builds additionally need the
Pico SDK ARM toolchain, CMake, Ninja, and an Embedded Swift SDK. Check the host
before creating a project:

```sh
swiftpico doctor
```

The doctor report tells you whether Swift, CMake, Ninja, `arm-none-eabi-gcc`,
PicoKit, the shared Pico SDK cache, the C callback probe, BOOTSEL volumes, and
serial devices are visible. A missing serial device is expected when the board
is unplugged; it is not a source-code error.

## 2. Create a project

```sh
mkdir -p ~/PicoProjects
cd ~/PicoProjects
swiftpico init --board pico --name Blink --template blink
cd Blink
```

Supported board values are `pico`, `pico_w` (also `pico-w`), `pico2`, and
`pico2_w` (also `pico2-w`). The board selects the chip and CMake configuration:
Pico/Pico W use RP2040; Pico 2/Pico 2 W use RP2350.

`init` creates a standalone package. By default it resolves the exact PicoKit
release recorded in the generated manifest. For local PicoKit development:

```sh
swiftpico init --board pico --name Blink --template blink \
  --pico-kit-path /path/to/PicoKit --path /tmp/Blink
```

Use `--skip-resolve` when creating an offline scaffold. It creates files but
does not download or resolve dependencies; run `swiftpico dependencies resolve`
later when the network and toolchain are available.

## 3. Read and change the program

The blink template uses PicoKit:

```swift
import PicoKit

@main
struct Blink {
    static func main() {
        pinMode(25, .output)
        while true {
            digitalWrite(25, .high)
            sleep(500)
            digitalWrite(25, .low)
            sleep(500)
        }
    }
}
```

On Pico W and Pico 2 W the template uses `BoardLED`, because the onboard LED
is controlled through the wireless chip rather than the RP2040/RP2350 GPIO 25.
See [Examples and templates](examples.md) for the other generated programs.

## 4. Build a UF2

```sh
swiftpico build
```

The first build may download and cache the Pico SDK by its pinned commit. The
firmware build is placed under `Firmware/build/`; the default UF2 is
`Firmware/build/<project-name>.uf2`.

Useful variants:

```sh
swiftpico build --configuration debug
swiftpico build --product OtherTarget
swiftpico build --swift-sdk <embedded-swift-sdk-id>
swiftpico build --verbose
swiftpico clean
```

SwiftPico refuses to build a host executable in place of firmware when no
Embedded Swift SDK is configured. Set `swiftSDK` in `swiftpico.json` or pass
`--swift-sdk`.

## 5. Flash over USB

With the board running its previous application, the normal command is:

```sh
swiftpico flash
```

SwiftPico first checks for an already-mounted BOOTSEL volume, then attempts the
ordinary USB serial reset when exactly one serial device is present, and uses
`picotool` as the USB fallback. It waits for the application to reappear before
reporting success.

Inspect the state when flashing fails:

```sh
swiftpico devices
swiftpico doctor
```

If BOOTSEL is already mounted, use the explicit compatibility path:

```sh
swiftpico flash --volume /Volumes/RPI-RP2
```

You can select another image or tool:

```sh
swiftpico flash --uf2 Firmware/build/Blink.uf2
swiftpico flash --picotool /path/to/picotool
```

## 6. Monitor USB serial

```sh
swiftpico monitor --reconnect
```

The monitor displays USB CDC output and forwards typed bytes to the board.
Press Ctrl-C to stop. The default baud is 115200; it is a host-side serial
setting and does not change USB CDC firmware behavior.

```sh
swiftpico monitor --device /dev/cu.usbmodemXXXX --baud 115200 --reconnect
```

`--reconnect` is useful after flashing because USB CDC disappears briefly and
re-enumerates. Without it, the monitor exits when the device disconnects.

## What success means at each step

| Step | Evidence | Next failure boundary |
| --- | --- | --- |
| `doctor` | host tools and project state are discoverable | installation or configuration |
| `build` | a board-specific UF2 exists | Swift/CMake/linker/toolchain |
| `flash` | the image was delivered and the board returned | USB/BOOTSEL/reset |
| `monitor` | CDC bytes can be exchanged | firmware output or serial ownership |
| application test | the external device behaves as expected | wiring, voltage, protocol, or driver |

Keep the first successful `serial` project as a USB baseline. When a richer
application fails, compare it with that baseline before changing flash or
monitor mechanisms.

## 7. The one-command loop

After editing source, this is convenient:

```sh
swiftpico make && swiftpico monitor --reconnect
```

`make` means build followed by flash; it does not start the monitor.
