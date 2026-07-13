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

localKitProject="$tmp/local-kit"
kit=$(CDPATH= cd -- "$root/../PicoKit" && pwd)
swift run swiftpico init --board pico --name LocalKit --template blink --path "$localKitProject" --skip-resolve --pico-kit-path "$kit"
grep -Fq '.package(path: "'"$kit"'")' "$localKitProject/Package.swift"
grep -Fq '"picoKitPath" : "'"$kit"'"' "$localKitProject/swiftpico.json"

libraryProject="$tmp/libraries"
swift run swiftpico init --board pico --name LibraryTest --template blink --path "$libraryProject" --skip-resolve
swift run swiftpico add swift --context "$libraryProject/swiftpico.json" \
    --url https://github.com/example/EmbeddedMath.git --from 1.0.0 \
    --package EmbeddedMath --product EmbeddedMath --target EmbeddedMath --skip-resolve
grep -Fq '.package(name: "EmbeddedMath", url: "https://github.com/example/EmbeddedMath.git", from: "1.0.0")' "$libraryProject/Package.swift"
grep -Fq '.product(name: "EmbeddedMath", package: "EmbeddedMath")' "$libraryProject/Package.swift"
grep -Fq 'picokit_add_swift_library(EmbeddedMath' "$libraryProject/Firmware/Dependencies.cmake"
grep -Fq '.build/checkouts/EmbeddedMath/Sources/EmbeddedMath' "$libraryProject/Firmware/Dependencies.cmake"
swift run swiftpico add c --context "$libraryProject/swiftpico.json" \
    --url https://github.com/example/tiny-driver.git --tag v1.2.0 --target tiny_driver
grep -Fq 'FetchContent_Declare(tiny_driver' "$libraryProject/Firmware/Dependencies.cmake"
grep -Fq 'target_link_libraries(${PICOKIT_PRODUCT} PRIVATE tiny_driver)' "$libraryProject/Firmware/Dependencies.cmake"

flashProject="$tmp/flash"
swift run swiftpico init --board pico --name FlashTest --template serial --path "$flashProject" --skip-resolve
mkdir -p "$flashProject/Firmware/build"
touch "$flashProject/Firmware/build/FlashTest.uf2"
export SWIFTPICO_TEST_LOG="$tmp/picotool-args"
swift run swiftpico flash --context "$flashProject/swiftpico.json" --picotool "$root/Tests/fake-picotool.sh"
grep -qx 'load' "$SWIFTPICO_TEST_LOG"
grep -qx '\-f' "$SWIFTPICO_TEST_LOG"
grep -qx "$flashProject/Firmware/build/FlashTest.uf2" "$SWIFTPICO_TEST_LOG"
