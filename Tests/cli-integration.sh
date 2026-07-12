#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cd "$root"
swift run swiftpico help | grep -q "PicoKit"
swift run swiftpico template | grep -q "watchdog"

for template in blink serial adc pwm i2c spi interrupt watchdog; do
    project="$tmp/$template"
    swift run swiftpico init --board pico-w --name "$template" --template "$template" --path "$project" --skip-resolve
    test -f "$project/Package.swift"
    test -f "$project/Firmware/CMakeLists.txt"
    test -f "$project/swiftpico"
    grep -q 'import PicoKit' "$project/Sources/$template/main.swift"
done

grep -q 'github.com/kyooni18/PicoKit.git' "$tmp/serial/Package.swift"
grep -q 'PICOKIT_ROOT}/Firmware/CMakeLists.txt' "$tmp/serial/Firmware/CMakeLists.txt"
grep -Fq 'pico_enable_stdio_usb(${PICOKIT_PRODUCT} 1)' "$tmp/serial/Firmware/CMakeLists.txt"
grep -Fq 'pico_enable_stdio_uart(${PICOKIT_PRODUCT} 0)' "$tmp/serial/Firmware/CMakeLists.txt"
grep -q 'Serial.println' "$tmp/serial/Sources/serial/main.swift"
grep -q 'sleep(' "$tmp/serial/Sources/serial/main.swift"
grep -q 'Serial.println' "$tmp/blink/Sources/blink/main.swift"
grep -q 'BoardLED' "$tmp/blink/Sources/blink/main.swift"

flashProject="$tmp/flash"
swift run swiftpico init --board pico --name FlashTest --template serial --path "$flashProject" --skip-resolve
mkdir -p "$flashProject/Firmware/build"
touch "$flashProject/Firmware/build/FlashTest.uf2"
export SWIFTPICO_TEST_LOG="$tmp/picotool-args"
swift run swiftpico flash --context "$flashProject/swiftpico.json" --picotool "$root/Tests/fake-picotool.sh"
grep -qx 'load' "$SWIFTPICO_TEST_LOG"
grep -qx '\-f' "$SWIFTPICO_TEST_LOG"
grep -qx "$flashProject/Firmware/build/FlashTest.uf2" "$SWIFTPICO_TEST_LOG"
