# SwiftPico documentation

SwiftPico is the host-side tool for building and using [PicoKit](https://github.com/kyooni18/PicoKit)
firmware with Embedded Swift. A SwiftPico project has two parts:

1. SwiftPico discovers the project, resolves PicoKit and firmware dependencies,
   configures CMake, and controls the USB device.
2. PicoKit supplies the embedded Swift APIs and Pico SDK bridge that are linked
   into the firmware.

Read the guides in this order if you are new to the project:

- [Beginner's guide](getting-started.md) — install, create, build, flash, and monitor a board.
- [Examples and templates](examples.md) — complete programs and how to adapt them.
- [Project anatomy](project-anatomy.md) — understand every generated file and build stage.
- [Command reference](command-reference.md) — every command, alias, option, and expected use.
- [Configuration reference](configuration.md) — `swiftpico.json`, dependency files, and CMake.
- [External libraries](external-libraries.md) — Swift packages, C/C++, archives, adapters, and locks.
- [Troubleshooting](troubleshooting.md) — diagnosis by symptom and recovery command.

For the embedded API itself, use the [PicoKit API reference](https://github.com/kyooni18/PicoKit/blob/main/Docs/api-reference.md).
SwiftPico does not duplicate PicoKit's GPIO, serial, bus, ADC, PWM, timing, or
interrupt API; it makes those APIs buildable and flashable.

## The shortest working loop

```sh
swiftpico init --board pico --name Blink --template blink
cd Blink
swiftpico build
swiftpico flash
swiftpico monitor --reconnect
```

If a project already exists, run project-aware commands from it or any child
directory. SwiftPico walks up parent directories looking for `swiftpico.json`
(and accepts legacy `picokit.json`). Commands that do not need project files,
such as `devices` and `monitor`, can run from anywhere.

## Scope and terminology

**Host** means the macOS machine running SwiftPico. **Target** means the Pico
firmware compiled for RP2040 or RP2350. **USB CDC** is the serial device exposed
by the running firmware. **BOOTSEL** is the removable USB storage mode used by
the bootloader. **UF2** is the firmware image copied to BOOTSEL or loaded by
`picotool`.

## Documentation contract

SwiftPico documents host orchestration; PicoKit documents the embedded API.
When a workflow crosses both repositories, use the SwiftPico guide for project,
build, flash, monitor, and dependency state, then use the PicoKit guide for
pin behavior, bus semantics, timing, and runtime limits. A successful SwiftPico
command proves a host stage only; it does not prove external wiring or device
protocol correctness.

The implementation-backed checks are:

```sh
sh Tests/docs-validation.sh
sh Tests/cli-integration.sh
```
