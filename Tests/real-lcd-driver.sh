#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
kit=${PICOKIT_TEST_ROOT:-"$root/../PicoKit"}
kit=$(CDPATH= cd -- "$kit" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if [ -d /opt/homebrew/bin ]; then
    PATH="/opt/homebrew/bin:$PATH"
    export PATH
fi
swift build --package-path "$root" --product swiftpico
cli="$root/.build/debug/swiftpico"

project="$tmp/RealLCD"
"$cli" init --board pico --name RealLCD --template blink \
    --path "$project" --skip-resolve --pico-kit-path "$kit"
cp "$root/Tests/Fixtures/RealLCD/dependencies.json" "$project/Firmware/dependencies.json"
cp "$root/Tests/Fixtures/RealLCD/AppInterop.h" "$project/Firmware/Interop/AppInterop.h"
cp "$root/Tests/Fixtures/RealLCD/ST7789Adapter.c" "$project/Firmware/Interop/ST7789Adapter.c"
cp "$root/Tests/Fixtures/RealLCD/main.swift" "$project/Sources/RealLCD/main.swift"

"$cli" dependencies resolve --context "$project/swiftpico.json"
grep -q '42ec0b358377d11e53513247c5b50acc48df2245' "$project/Firmware/dependencies.lock"
"$cli" build --configuration release --context "$project/swiftpico.json"
test -f "$project/Firmware/build/RealLCD.uf2"
echo "SwiftPico real external ST7789 driver build passed"
