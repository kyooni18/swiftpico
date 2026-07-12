# SwiftPico

SwiftPico is the command-line companion to [PicoKit](https://github.com/kyooni18/PicoKit). It creates Pico firmware projects, builds them with Embedded Swift, flashes them over USB, and monitors serial output.

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

`init` creates a standalone Swift package with a tagged PicoKit dependency, a board-specific `swiftpico.json`, a firmware CMake entrypoint, and a local `swiftpico` launcher. Add `--pico-kit-version VERSION` when you need a different PicoKit release, or `--skip-resolve` for an offline scaffold.

## Flashing

The normal flash path uses the USB interface directly:

```sh
swiftpico flash
```

SwiftPico runs `picotool load -f`, which asks compatible USB-stdio firmware to reboot into the bootloader, loads the UF2, and returns to the application. If you already mounted a BOOTSEL volume, the explicit compatibility path remains available:

```sh
swiftpico flash --volume /Volumes/RPI-RP2
```

If the firmware does not expose picotool's vendor reset interface, SwiftPico
falls back to the Pico SDK's USB CDC 1200-baud reset and copies the UF2 to the
BOOTSEL volume after it mounts. This still requires no BOOTSEL button press.

## Development

```sh
swift build
swift run swiftpico help
sh Tests/cli-integration.sh
```
