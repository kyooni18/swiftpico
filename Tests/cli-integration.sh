#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cd "$root"
swift build --product swiftpico
cli="$root/.build/debug/swiftpico"
"$cli" help | grep -q "PicoKit"
"$cli" template | grep -q "watchdog"

for template in blink serial adc pwm i2c spi interrupt watchdog; do
    project="$tmp/$template"
    "$cli" init --board pico-w --name "$template" --template "$template" --path "$project" --skip-resolve
    test -f "$project/Package.swift"
    test -f "$project/Firmware/CMakeLists.txt"
    test -f "$project/Firmware/dependencies.json"
    test -f "$project/Firmware/Interop/AppInterop.h"
    test -f "$project/Firmware/Interop/Callbacks.h"
    test -f "$project/swiftpico"
    grep -q 'import PicoKit' "$project/Sources/$template/main.swift"
done

progressProject="$tmp/progress"
progressOutput=$("$cli" init --board pico --name Progress --template blink --path "$progressProject" --skip-resolve)
printf '%s\n' "$progressOutput" | grep -q 'Starting SwiftPico project initialization'
printf '%s\n' "$progressOutput" | grep -q 'Creating project configuration and source files'
printf '%s\n' "$progressOutput" | grep -q 'Skipping dependency resolution'

grep -q 'github.com/kyooni18/PicoKit.git' "$tmp/serial/Package.swift"
grep -q 'PICO_SDK_PATH must point to the shared Pico SDK' "$tmp/serial/Firmware/CMakeLists.txt"
! grep -q 'Vendor/pico-sdk' "$tmp/serial/Firmware/CMakeLists.txt"
grep -Fq 'initialize_usb_interface_at_start' "$tmp/serial/swiftpico.json"
! grep -Fq 'pico_enable_stdio_usb(${PICOKIT_PRODUCT} 1)' "$tmp/serial/Firmware/CMakeLists.txt"
grep -q 'Serial.read()' "$tmp/serial/Sources/serial/main.swift"
grep -Fq 'Serial.write(byte)' "$tmp/serial/Sources/serial/main.swift"
! grep -Fq 'Serial.println()' "$tmp/serial/Sources/serial/main.swift"
grep -q 'sleepMicroseconds(100)' "$tmp/serial/Sources/serial/main.swift"
grep -q 'Serial.println' "$tmp/blink/Sources/blink/main.swift"
grep -q 'BoardLED' "$tmp/blink/Sources/blink/main.swift"

localKitProject="$tmp/local-kit"
kit=${PICOKIT_TEST_ROOT:-"$root/../PicoKit"}
kit=$(CDPATH= cd -- "$kit" && pwd)
"$cli" init --board pico --name LocalKit --template blink --path "$localKitProject" --skip-resolve --pico-kit-path "$kit"
grep -Fq '.package(path: "'"$kit"'")' "$localKitProject/Package.swift"
grep -Fq '"picoKitPath"' "$localKitProject/swiftpico.json"
grep -Fq 'PicoKit' "$localKitProject/swiftpico.json"
test -f "$localKitProject/Firmware/dependencies.lock"
grep -Fq '"exactCommit"' "$localKitProject/Firmware/dependencies.lock"

libraryProject="$tmp/libraries"
"$cli" init --board pico --name LibraryTest --template blink --path "$libraryProject" --skip-resolve
"$cli" add swift --context "$libraryProject/swiftpico.json" \
    --url https://github.com/example/EmbeddedMath.git --from 1.0.0 \
    --package EmbeddedMath --product EmbeddedMath --target EmbeddedMath --skip-resolve
grep -Fq '.package(name: "EmbeddedMath", url: "https://github.com/example/EmbeddedMath.git", exact: "1.0.0")' "$libraryProject/Package.swift"
grep -Fq '.product(name: "EmbeddedMath", package: "EmbeddedMath")' "$libraryProject/Package.swift"
grep -Fq '"integration" : "swiftSources"' "$libraryProject/Firmware/dependencies.json"
"$cli" add c --context "$libraryProject/swiftpico.json" \
    --url https://github.com/example/tiny-driver.git --tag v1.2.0 --target tiny_driver --skip-resolve
grep -Fq '"name" : "tiny_driver"' "$libraryProject/Firmware/dependencies.json"
"$cli" add c --context "$libraryProject/swiftpico.json" \
    --url https://github.com/example/vendor-driver.git --tag v2.0.0 --target Vendor::driver --skip-resolve
grep -Fq '"name" : "vendor_driver"' "$libraryProject/Firmware/dependencies.json"
grep -Fq '"target" : "Vendor::driver"' "$libraryProject/Firmware/dependencies.json"
"$cli" dependencies show --context "$libraryProject/swiftpico.json" | grep -q tiny_driver
"$cli" dependencies remove tiny_driver --context "$libraryProject/swiftpico.json"
! grep -Fq '"name" : "tiny_driver"' "$libraryProject/Firmware/dependencies.json"
"$cli" dependencies remove vendor_driver --context "$libraryProject/swiftpico.json"
! grep -Fq '"name" : "vendor_driver"' "$libraryProject/Firmware/dependencies.json"
"$cli" dependencies remove EmbeddedMath --context "$libraryProject/swiftpico.json"
! grep -Fq 'EmbeddedMath' "$libraryProject/Package.swift"

migrationProject="$tmp/migration"
"$cli" init --board pico --name MigrationTest --template blink --path "$migrationProject" \
    --skip-resolve --pico-kit-path "$kit"
rm -rf "$migrationProject/Firmware/Generated" "$migrationProject/Firmware/Interop"
rm -f "$migrationProject/Firmware/dependencies.json" "$migrationProject/Firmware/dependencies.lock"
touch "$migrationProject/Firmware/Dependencies.cmake"
"$cli" dependencies migrate --context "$migrationProject/swiftpico.json"
test -f "$migrationProject/Firmware/Dependencies.cmake"
test -f "$migrationProject/Firmware/dependencies.json"
test -f "$migrationProject/Firmware/Interop/AppInterop.h"
resolveOutput=$("$cli" dependencies resolve --context "$migrationProject/swiftpico.json")
printf '%s\n' "$resolveOutput" | grep -q 'Resolving Swift package dependencies in'
printf '%s\n' "$resolveOutput" | grep -q 'Writing Firmware/dependencies.lock'
printf '%s\n' "$resolveOutput" | grep -q 'Generating Firmware/Generated/Dependencies.cmake'
test -f "$migrationProject/Firmware/dependencies.lock"

flashProject="$tmp/flash"
"$cli" init --board pico --name FlashTest --template serial --path "$flashProject" --skip-resolve
perl -pi -e 's/"initialize_usb_interface_at_start"\s*:\s*true/"initialize_usb_interface_at_start" : false/' "$flashProject/swiftpico.json"
mkdir -p "$flashProject/Firmware/build"
touch "$flashProject/Firmware/build/FlashTest.uf2"
export SWIFTPICO_TEST_LOG="$tmp/picotool-args"
"$cli" flash --context "$flashProject/swiftpico.json" --picotool "$root/Tests/fake-picotool.sh"
grep -qx 'load' "$SWIFTPICO_TEST_LOG"
grep -qx '\-F' "$SWIFTPICO_TEST_LOG"
grep -qx '\-v' "$SWIFTPICO_TEST_LOG"
grep -qx "$flashProject/Firmware/build/FlashTest.uf2" "$SWIFTPICO_TEST_LOG"
grep -qx 'reboot' "$SWIFTPICO_TEST_LOG"
grep -qx '\-\-application' "$SWIFTPICO_TEST_LOG"

echo "SwiftPico CLI integration passed"
