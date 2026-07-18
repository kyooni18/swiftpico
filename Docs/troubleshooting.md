# Troubleshooting

Start every diagnosis with:

```sh
swiftpico doctor
swiftpico devices
swiftpico info
```

## Context or toolchain errors

For `no swiftpico.json ... found`, run from the project directory or pass
`--context /path/to/Blink/swiftpico.json`. For `arm-none-eabi-gcc was not found`,
install the Pico SDK ARM toolchain or set `PICO_TOOLCHAIN_PATH`, then rerun
`swiftpico doctor`.

For missing locks or generated CMake, run:

```sh
swiftpico dependencies resolve
swiftpico dependencies generate
swiftpico build
```

If the shared SDK cache is unavailable, set `picoSDKPath` to a valid checkout.
To relocate it, set `SWIFTPICO_CACHE_DIR`.

## Build failures

Clean the firmware configure state and rebuild:

```sh
swiftpico clean
swiftpico dependencies generate
swiftpico build --verbose
```

Read the first compiler or CMake error; later linker messages are often
consequences of that first failure. A missing Embedded Swift SDK is reported
explicitly; set `swiftSDK` in `swiftpico.json` or pass `--swift-sdk`.

## USB and serial failures

Confirm the board uses a data cable and run `swiftpico devices`. If USB startup
was disabled, `monitor` cannot discover CDC.

For multiple devices, select one:

```sh
swiftpico monitor --device /dev/cu.usbmodemXXXX --reconnect
```

For a BOOTSEL failure, use the mounted volume explicitly:

```sh
swiftpico flash --volume /Volumes/RPI-RP2
```

Otherwise reconnect while holding BOOTSEL and retry. A board visible as serial
but unable to transition to BOOTSEL indicates a host USB/reset boundary; it
does not by itself prove that the UF2 or source is wrong.

After flashing, use `--reconnect` because USB CDC re-enumerates, and stop other
serial programs that may own the device node.

## C/C++ import failures

Confirm the target exists with `swiftpico dependencies show`, regenerate CMake,
and place declarations in `Firmware/Interop/AppInterop.h` or a module under
`Firmware/Interop/Modules/`. Expose C++ through an `extern "C"` adapter rather
than importing an arbitrary CMake target directly into Swift.

## Evaluate before changing anything

Capture the exact command, project context, board state from `swiftpico devices`,
and the first stage failure. Then classify it:

- no context, schema, or missing file: project discovery/configuration;
- missing compiler, SDK, CMake, or lock: host environment/resolution;
- compiler or linker error: source, ABI, or dependency integration;
- BOOTSEL or serial disappearance: USB/reset ownership and enumeration;
- valid flash but wrong behavior: firmware runtime, wiring, or protocol.

This classification keeps a source error from being “fixed” by changing flash
commands and keeps a USB symptom from being misreported as a PicoKit API bug.

## Existing projects and schema errors

`swiftpico.json already exists` protects existing source and configuration; use
another destination or `--force` intentionally. An unsupported `schemaVersion`
requires a newer CLI. For a legacy dependency layout, run:

```sh
swiftpico dependencies migrate
```
