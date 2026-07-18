# External libraries

SwiftPico keeps application dependencies outside PicoKit. This lets a project
use a sensor, display, filesystem, or protocol library without changing the
core package.

## Embedded Swift package

```sh
swiftpico add swift \
  --url https://github.com/example/EmbeddedMath.git \
  --from 1.0.0 --package EmbeddedMath --product EmbeddedMath
```

The command adds the package to `Package.swift`, adds its product to the
application target, and records firmware metadata. Import it in Swift:

```swift
import PicoKit
import EmbeddedMath
```

The package must support the selected Embedded Swift target and avoid host-only
Foundation or unavailable runtime features.

## C or C++ CMake target

```sh
swiftpico add c --url https://github.com/example/tiny-driver.git \
  --tag v1.2.0 --target tiny_driver
swiftpico add cpp --url https://github.com/example/display-driver.git \
  --tag v3.0.0 --target Display::driver
```

The target may be namespaced with `::`. The exact commit is recorded by
`dependencies resolve`. C++ code should expose an `extern "C"` adapter to Swift:

```cpp
// Firmware/Interop/DisplayAdapter.cpp
extern "C" void display_begin() {
    display::Driver driver;
    driver.begin();
}
```

Declare that adapter in an application-owned header and expose it through the
project's module map or C bridge. Most Pico firmware configurations do not
support exceptions or RTTI.

## Source-only and header-only libraries

Use source integration when a repository does not export a usable CMake target:

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

Header-only libraries should be called through a small `.c` or C++ adapter.

## Resolution workflow

```sh
swiftpico dependencies show
swiftpico dependencies resolve
swiftpico dependencies generate
swiftpico dependencies update sensor_driver --revision v1.5.0
swiftpico dependencies remove sensor_driver
```

`show` reports manifest entries. `resolve` updates exact commits in
`dependencies.lock` and generated CMake. `generate` rebuilds CMake from the lock.
`update` changes intent only;
resolve it before building. `remove` also removes SwiftPM entries for Swift
dependencies.
