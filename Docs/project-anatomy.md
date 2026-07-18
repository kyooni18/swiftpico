# Project anatomy

`swiftpico init` creates a standalone project with this shape:

```text
Blink/
├── Package.swift
├── swiftpico.json
├── swiftpico
├── Sources/Blink/main.swift
├── Firmware/
│   ├── CMakeLists.txt
│   ├── dependencies.json
│   ├── dependencies.lock
│   ├── Generated/Dependencies.cmake
│   └── Interop/
│       ├── AppInterop.h
│       ├── Callbacks.h
│       └── Modules/
├── .build/
├── Firmware/build/
└── .swiftpico/firmware-build.json
```

`Package.swift` is the SwiftPM manifest. It imports PicoKit, and may contain
additional Embedded Swift package products. `Sources/<product>/main.swift` is
the application entry point. The `product` value in `swiftpico.json` selects
that source directory and becomes the firmware target name after unsafe
characters are replaced.

`Firmware/CMakeLists.txt` is a generated-project entrypoint. SwiftPico supplies
`PICOKIT_ROOT`, `PICO_SDK_PATH`, `PICO_BOARD`, `PICOKIT_PRODUCT`,
`PICOKIT_SOURCE`, and the USB setting when it configures CMake. Do not hard-code
the SDK path into this file unless maintaining a special project.

`Firmware/Interop/` belongs to the application. Put application C declarations
in `AppInterop.h`, C-to-Swift callback declarations in `Callbacks.h`, and
Clang module maps under `Modules/<Name>`. PicoKit's own bridge remains a package
implementation detail.

`dependencies.json` is editable intent. `dependencies.lock` records exact
commits and checksums. `Generated/Dependencies.cmake` is derived, read-only
build logic. Change the first two through the dependency commands, then
regenerate the third.

The shared Pico SDK cache is keyed by the revision in PicoKit's
`Vendor/pico-sdk.revision`. `SWIFTPICO_CACHE_DIR` changes the cache root. An
explicit `picoSDKPath` in `swiftpico.json` takes precedence over the shared
cache.

## Build stages

```text
Swift source + Package.swift
        │ swift compiler / Embedded Swift SDK
        ▼
Swift object + PicoKit bridge + C/C++ dependencies
        │ CMake + Ninja + Pico SDK linker
        ▼
Firmware/build/<product>.uf2
        │ picotool or BOOTSEL volume
        ▼
Pico application + USB CDC serial
```

Each firmware build records SwiftPico and PicoKit versions in
`.swiftpico/firmware-build.json`. A version change invalidates the firmware
build directory so stale bridge objects are not silently reused.

## Legacy projects

Context discovery still accepts `picokit.json`, and
`swiftpico dependencies migrate` preserves a legacy `Firmware/Dependencies.cmake`
while creating the v0.2 dependency and interop structure. New projects should
use `swiftpico.json`, `dependencies.json`, and the generated CMake file.

## Ownership map

| File or directory | Owned by | Safe change |
| --- | --- | --- |
| `Sources/<product>/main.swift` | application | edit freely |
| `Package.swift` | application/SwiftPM | use `add swift` or edit intentionally |
| `swiftpico.json` | application | configure board and host paths |
| `Firmware/dependencies.json` | application | edit intent |
| `Firmware/dependencies.lock` | resolver | regenerate through `resolve` |
| `Firmware/Generated/Dependencies.cmake` | generator | regenerate, do not hand-edit |
| `Firmware/Interop` | application | add adapters and module maps |
| `Firmware/CMakeLists.txt` | generated entrypoint | change only for a deliberate custom boundary |
| `Firmware/build`, `.build`, `.swiftpico` | tools | clean/regenerate as needed |

This map is the practical answer to “where should I fix it?”: source behavior
belongs in the application, dependency intent in the manifest, and derived
build behavior in the resolver output.
