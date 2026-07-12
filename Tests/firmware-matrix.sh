#!/bin/sh
set -eu

# Requires CMake, Ninja, an Embedded Swift toolchain, and arm-none-eabi-gcc.
# Run this in CI or on a firmware build host; it intentionally builds the
# generated project for every supported Raspberry Pi board definition.
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

for board in pico pico_w pico2 pico2_w; do
    project="$tmp/$board"
    PICOKIT_ROOT="$root" swift run --package-path "$root" swiftpico init --board "$board" --name MatrixApp --template blink --path "$project"
    (
        cd "$project"
        PICOKIT_ROOT="$root" swift run --package-path "$root" swiftpico build --configuration release --context "$project/swiftpico.json"
    )
done
