#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
kit=${PICOKIT_TEST_ROOT:-"$root/../PicoKit"}
kit=$(CDPATH= cd -- "$kit" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export PATH="/opt/homebrew/bin:$PATH"
swift build --package-path "$root" --product swiftpico
cli="$root/.build/debug/swiftpico"
project="$tmp/InteropFixture"

"$cli" init --board pico --name InteropFixture --template blink \
    --path "$project" --skip-resolve --pico-kit-path "$kit"

mkdir -p "$project/Firmware/Interop/Modules/MockLCD"
cp -R "$root/Tests/Fixtures/Interop/." "$project/Firmware/Interop/"
cp "$root/Tests/Fixtures/InteropMain.swift" "$project/Sources/InteropFixture/main.swift"

if [ -z "${SWIFTPICO_VALIDATE_ONLY:-}" ]; then
    "$cli" build --configuration release --context "$project/swiftpico.json"
    test -f "$project/Firmware/build/InteropFixture.uf2"
else
    test -f "$project/Firmware/Interop/AppInterop.c"
    test -f "$project/Firmware/Interop/CppAdapter.cpp"
    grep -q 'import MockLCD' "$project/Sources/InteropFixture/main.swift"
fi
echo "SwiftPico application interop fixture passed"
