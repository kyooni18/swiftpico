# SwiftPico

SwiftPico is the command-line companion to [PicoKit](https://github.com/kyooni18/PicoKit). It creates Pico firmware projects, builds them with Embedded Swift, flashes them over USB, and provides an interactive serial terminal.

The CLI itself has no PicoKit package dependency; it only writes the selected
PicoKit release into generated projects. This keeps installation and release
builds small while firmware still uses the complete library and SDK checkout.

SwiftPico supports macOS 13 or newer on both Apple Silicon (`arm64`) and Intel
(`x86_64`). Homebrew builds the executable natively for the host architecture.

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
`Serial.write(_:)`; it deliberately does not translate line endings. That makes
it useful for both interactive bring-up and byte-level USB hardware checks.

`init` creates a standalone Swift package pinned to one exact PicoKit release, a board-specific `swiftpico.json`, a firmware CMake entrypoint, application-owned interop files, and a local `swiftpico` launcher. Add `--pico-kit-version VERSION` to select the release explicitly, or `--skip-resolve` for an offline scaffold. Use `--pico-kit-path /path/to/PicoKit` to develop against a local checkout before a PicoKit change is released as a tag.

Pico SDK is cached once per pinned SDK commit rather than initialized inside every project’s PicoKit checkout. `swiftpico build` creates the shared cache automatically. By default it uses the platform cache directory; set `SWIFTPICO_CACHE_DIR` to place it on a shared drive or in your CI cache. A project can still set `picoSDKPath` in `swiftpico.json` to use an explicit SDK checkout.

Generated firmware enables the Pico SDK USB stdio reset interface and disables UART stdio:

```cmake
pico_enable_stdio_usb(your_target 1)
pico_enable_stdio_uart(your_target 0)
```

USB startup is enabled by default. To build a firmware image without USB CDC or
the picotool reset interface, add this to `swiftpico.json` and rebuild:

```json
{
  "initialize_usb_interface_at_start": false
}
```

## Flashing

The normal flash path uses the USB interface directly:

```sh
swiftpico flash
```

SwiftPico runs `picotool load -F` when available, keeping BOOTSEL connected until one explicit application reboot completes the transfer. This avoids racing USB re-enumeration after a flash. If `picotool` is unavailable or cannot reset the board, SwiftPico uses the USB CDC 1200-baud reset exposed by the same USB stdio setting, waits for BOOTSEL storage, and copies the UF2. If you already mounted a BOOTSEL volume, the explicit compatibility path remains available:

```sh
swiftpico flash --volume /Volumes/RPI-RP2
```

If the firmware does not expose picotool's vendor reset interface, SwiftPico
falls back to the Pico SDK's USB CDC 1200-baud reset and copies the UF2 to the
BOOTSEL volume after it mounts. This still requires no BOOTSEL button press.

## External libraries

SwiftPico 0.2 records editable intent in `Firmware/dependencies.json`, exact Git
commits in `Firmware/dependencies.lock`, and read-only build logic in
`Firmware/Generated/Dependencies.cmake`. Ordinary builds consume the lock and
do not select newer dependency revisions. Legacy `Firmware/Dependencies.cmake`
continues to work during explicit migration. For repositories containing more
than one CMake project, set `cmakeSubdirectory` on the dependency to configure
only the project that owns the selected target.

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

Manage resolution explicitly:

```sh
swiftpico dependencies resolve
swiftpico dependencies show
swiftpico dependencies update tiny_driver --revision v1.3.0
swiftpico dependencies remove tiny_driver
swiftpico dependencies migrate   # preserves a legacy Dependencies.cmake
```

The schema supports the common embedded-library layouts: Git repositories,
local/vendor directories, and checksum-pinned source archives; CMake targets
(including namespaced targets such as `Vendor::driver`), explicit C/C++ source
lists, and header-only libraries. It also carries include directories,
configuration-header directories, compiler definitions/options, CMake cache
options, board conditions, adapters, module metadata, and resource ownership.

For example, a source-only archive or a locally vendored driver can remain
outside PicoKit while still being explicit in the application manifest:

```json
{
  "name": "sensor_driver",
  "language": "c",
  "sourceType": "archive",
  "repositoryURL": "https://example.com/sensor-driver-1.4.0.tar.gz",
  "revision": "1.4.0",
  "archiveSHA256": "<64-character SHA-256>",
  "integration": "sources",
  "sources": ["src/sensor.c"],
  "includeDirectories": ["include"],
  "configurationHeaders": ["config/sensor_config.h"],
  "compileDefinitions": ["SENSOR_NO_FLOAT=1"]
}
```

Use `"sourceType": "local"` with a directory path in `repositoryURL` for a
development checkout; Git-backed local directories record their current commit
in the lock file. Header-only libraries should be called through a `.c`
adapter. C++ libraries should expose an `extern "C"` adapter and compile without
exceptions or RTTI.

Application headers belong in `Firmware/Interop/AppInterop.h`; callbacks in
`Callbacks.h`; Clang module maps in `Firmware/Interop/Modules/<Name>`. The
PicoKit internal bridging header is never modified.

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
