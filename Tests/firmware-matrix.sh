#!/bin/sh
set -eu

# Requires CMake, Ninja, an Embedded Swift toolchain, and arm-none-eabi-gcc.
# Run this in CI or on a firmware build host; it intentionally builds the
# generated project for every supported Raspberry Pi board definition.
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export PATH="/opt/homebrew/bin:$PATH"
kit=${PICOKIT_TEST_ROOT:-"$root/../PicoKit"}
kit=$(CDPATH= cd -- "$kit" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
swift build --package-path "$root" --product swiftpico
cli="$root/.build/debug/swiftpico"

for board in pico pico_w pico2 pico2_w; do
    project="$tmp/$board"
    "$cli" init --board "$board" --name MatrixApp --template blink --path "$project" --pico-kit-path "$kit"
    grep -q '"schemaVersion" : 1' "$project/swiftpico.json"
    grep -q "\"board\" : \"$board\"" "$project/swiftpico.json"
    test -f "$project/Firmware/Generated/Dependencies.cmake"
    if [ -z "${SWIFTPICO_VALIDATE_ONLY:-}" ]; then
        "$cli" build --configuration release --context "$project/swiftpico.json"
    fi
    if [ "$board" = pico ] && [ -z "${SWIFTPICO_VALIDATE_ONLY:-}" ]; then
        state="$project/.swiftpico/firmware-build.json"
        test -f "$state"
        touch "$project/Firmware/build/stale-version-marker"
        perl -0pi -e 's/"swiftPicoVersion" : "[^"]+"/"swiftPicoVersion" : "older-build"/' "$state"
        "$cli" build --configuration release --context "$project/swiftpico.json"
        test ! -e "$project/Firmware/build/stale-version-marker"
    fi
done

# Compile the duplex USB path on both supported MCU families.
for board in pico pico2_w; do
    project="$tmp/serial-$board"
    "$cli" init --board "$board" --name SerialMatrix --template serial --path "$project" --pico-kit-path "$kit"
    grep -q 'Serial.read()' "$project/Sources/SerialMatrix/main.swift"
    if [ -z "${SWIFTPICO_VALIDATE_ONLY:-}" ]; then
        "$cli" build --configuration release --context "$project/swiftpico.json"
    fi
done

echo "SwiftPico firmware matrix passed"
