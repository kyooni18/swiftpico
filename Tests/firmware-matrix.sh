#!/bin/sh
set -eu

# Requires CMake, Ninja, an Embedded Swift toolchain, and arm-none-eabi-gcc.
# Run this in CI or on a firmware build host; it intentionally builds the
# generated project for every supported Raspberry Pi board definition.
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
kit=${PICOKIT_TEST_ROOT:-"$root/../PicoKit"}
kit=$(CDPATH= cd -- "$kit" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
swift build --package-path "$root" --product swiftpico
cli="$root/.build/debug/swiftpico"

for board in pico pico_w pico2 pico2_w; do
    project="$tmp/$board"
    "$cli" init --board "$board" --name MatrixApp --template blink --path "$project" --pico-kit-path "$kit"
    (
        cd "$project"
        "$cli" build --configuration release --context "$project/swiftpico.json"
    )
    if [ "$board" = pico ]; then
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
    "$cli" build --configuration release --context "$project/swiftpico.json"
done

echo "SwiftPico firmware matrix passed"
