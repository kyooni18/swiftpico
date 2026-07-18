# Configuration reference

The generated `swiftpico.json` is JSON with schema version 1. A minimal hand-
written configuration is:

```json
{
  "schemaVersion": 1,
  "board": "pico",
  "firmwareDirectory": "Firmware",
  "picoKitURL": "https://github.com/kyooni18/PicoKit.git",
  "picoKitVersion": "0.2.12",
  "product": "Blink",
  "configuration": "release",
  "uf2": "Firmware/build/Blink.uf2",
  "initialize_usb_interface_at_start": true,
  "openOCD": "openocd",
  "openOCDConfig": ["interface/cmsis-dap.cfg", "target/rp2040.cfg"]
}
```

| Field | Meaning |
| --- | --- |
| `schemaVersion` | Must be `1`; omitted means legacy v0. |
| `board` | `pico`, `pico_w`, `pico2`, or `pico2_w`. |
| `firmwareDirectory` | CMake firmware directory, normally `Firmware`. |
| `picoSDKPath` | Optional explicit Pico SDK checkout; overrides the shared cache. |
| `picoKitPath` | Optional local PicoKit checkout. |
| `picoKitURL` / `picoKitVersion` | Git source and exact release for PicoKit. |
| `picotool` | Optional configured picotool path. |
| `swiftSDK` | Embedded Swift SDK identifier used when building. |
| `product` | Swift source target and firmware product override. |
| `configuration` | Default `debug` or `release` build configuration. |
| `uf2` | Default UF2 path used by flash. |
| `openOCD` | OpenOCD executable, default `openocd`. |
| `openOCDConfig` | OpenOCD `-f` configuration files. |

Paths can be absolute or relative to the directory containing the JSON file.

## USB setting

USB startup is enabled by default. To intentionally build firmware without the
USB CDC/reset interface:

```json
{ "initialize_usb_interface_at_start": false }
```

This removes the normal automatic serial-reset route and makes monitor and
picotool workflows unavailable unless the board is put in BOOTSEL manually or
another debug/programming path is provided.

## Dependency files

`Firmware/dependencies.json` describes editable intent. The common fields are
`name`, `language` (`swift`, `c`, or `cpp`), `sourceType` (`git`, `local`, or
`archive`), `repositoryURL`, `revision`, `integration` (`cmakeTarget`,
`sources`, `swiftSources`, or header-only forms), `target`, `sources`,
`includeDirectories`, `configurationHeaders`, `compileDefinitions`, compiler
options, CMake options, board conditions, adapters, module metadata, and
resource ownership.

`dependencies.lock` is the reproducibility boundary. Change intent and run
`swiftpico dependencies resolve`; `Firmware/Generated/Dependencies.cmake` is
derived from that lock and should be regenerated rather than edited directly.
