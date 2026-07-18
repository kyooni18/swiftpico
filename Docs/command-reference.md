# Command reference

Commands search the current directory and its parents for `swiftpico.json` or
legacy `picokit.json`. Use `--context PATH` on commands that support it when
working outside that tree.

## Project creation

`swiftpico init` (alias `new`) creates a project.

```text
--board BOARD             pico, pico_w, pico2, or pico2_w; default pico
--name NAME               project and default product name; default PicoApp
--template NAME           blink, serial, adc, pwm, i2c, spi, interrupt, watchdog
--path PATH               exact destination instead of the current directory/name
--force                   allow an existing swiftpico.json to be overwritten
--pico-kit-url URL        PicoKit Git URL
--pico-kit-version VER   exact PicoKit version recorded in the package
--pico-kit-path PATH     local PicoKit checkout instead of a Git package
--skip-resolve            create metadata without network resolution
```

`template` lists the available templates.

## Build and cleanup

`swiftpico build` (alias `b`) configures and builds the firmware.

```text
--configuration debug|release   override swiftpico.json; default release
--swift-sdk SDK                 Embedded Swift SDK identifier
--product PRODUCT               source target and firmware product override
--verbose                       show verbose CMake/Swift build commands
```

`swiftpico clean` (alias `c`) removes `Firmware/build` for firmware projects or
runs `swift package clean` for older SwiftPM-only contexts.

`swiftpico make` (alias `m`) runs build and then flash.

## Flashing and monitoring

`swiftpico flash` (aliases `upload`, `f`) loads a UF2 over USB.

```text
--uf2 PATH             image override; otherwise the configured uf2 path
--volume PATH          explicit mounted BOOTSEL volume
--picotool PATH        explicit picotool executable
```

`swiftpico monitor` (aliases `serial`, `mon`) opens USB CDC.

```text
--device PATH          explicit serial device; required when several exist
--baud RATE            positive rate up to 4,000,000; default 115200
--reconnect            retry after CDC disconnect/re-enumeration
```

`swiftpico devices` (alias `list`) prints BOOTSEL volumes and serial devices.

`swiftpico debug` starts OpenOCD:

```text
--openocd PATH         executable override
--target TARGET        optional OpenOCD target-remote command
```

OpenOCD config files come from `openOCDConfig` in `swiftpico.json`.

## Inspection and diagnostics

`swiftpico info` prints the selected project root, board, product, build
configuration, firmware directory, SDK, UF2, and OpenOCD settings.

`swiftpico doctor` checks host tools, PicoKit/SDK/bridge resolution, project
locks and generated CMake, build state, USB state, and a C-to-Swift callback
probe. Use `--context PATH` to diagnose a project from another directory.

## Dependencies

```text
swiftpico add swift --url URL --from VERSION --package PACKAGE --product PRODUCT
                     [--target TARGET] [--skip-resolve]
swiftpico add c|cpp --url URL --tag TAG --target CMAKE_TARGET [--name NAME]
                     [--skip-resolve]
swiftpico dependencies resolve
swiftpico dependencies generate
swiftpico dependencies show
swiftpico dependencies update NAME --revision REVISION
swiftpico dependencies remove NAME
swiftpico dependencies migrate
```

`add swift` updates both `Package.swift` and firmware metadata. `add c` and
`add cpp` record a CMake target. `resolve` selects exact commits and regenerates
the lock and CMake files. `generate` only regenerates CMake from the lock.

## Context, aliases, and failure behavior

`new`, `b`, `f`, `upload`, `m`, `c`, `serial`, `mon`, `diagnose`, and `deps` are
aliases shown in the sections above; they do not create a second implementation
or a different project format. Project-aware commands accept `--context PATH`
where the implementation needs a JSON context. `devices`, `template`, `help`,
and `monitor` can operate without a project context.

On failure SwiftPico reports a stage (`configure`, `compile`, `flash`, or
`monitor`) and a recovery command. Treat the first reported stage as the host
boundary to investigate; a later CMake or linker message may only be a
consequence of the first error.
