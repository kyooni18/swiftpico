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
printf '%s\n' "$progressOutput" | grep -Fq "Destination: $progressProject"
printf '%s\n' "$progressOutput" | grep -q 'Creating project configuration and source files'
printf '%s\n' "$progressOutput" | grep -q 'Skipping dependency resolution'

invalidProject="$tmp/invalid-name"
invalidOutput="$tmp/invalid-name.log"
if "$cli" init --board pico --name "../escape" --path "$invalidProject" --skip-resolve >"$invalidOutput" 2>&1; then
    echo "invalid project name unexpectedly succeeded" >&2
    exit 1
fi
test ! -e "$invalidProject/swiftpico.json"
grep -q 'invalid project name' "$invalidOutput"

controlProject="$tmp/control-name"
controlOutput="$tmp/control-name.log"
controlName=$(printf 'line\nfeed')
if "$cli" init --board pico --name "$controlName" --path "$controlProject" --skip-resolve >"$controlOutput" 2>&1; then
    echo "control-character project name unexpectedly succeeded" >&2
    exit 1
fi
test ! -e "$controlProject/swiftpico.json"
! grep -q '^feed' "$controlOutput"
grep -q 'invalid project name' "$controlOutput"

incompleteProject="$tmp/incomplete"
mkdir -p "$incompleteProject/Sources/Incomplete"
printf '%s\n' 'struct ExistingSource {}' >"$incompleteProject/Sources/Incomplete/main.swift"
incompleteOutput="$tmp/incomplete.log"
if "$cli" init --board pico --name Incomplete --template blink --path "$incompleteProject" --skip-resolve >"$incompleteOutput" 2>&1; then
    echo "incomplete project unexpectedly succeeded without --force" >&2
    exit 1
fi
test ! -e "$incompleteProject/swiftpico.json"
grep -q 'incomplete SwiftPico project' "$incompleteOutput"
"$cli" init --board pico --name Incomplete --template blink --path "$incompleteProject" --skip-resolve --force
for generated in swiftpico.json Package.swift Firmware/CMakeLists.txt Firmware/dependencies.json Firmware/Interop/AppInterop.h Firmware/Interop/Callbacks.h swiftpico .gitignore Sources/Incomplete/main.swift; do
    test -f "$incompleteProject/$generated"
done

grep -q 'github.com/kyooni18/PicoKit.git' "$tmp/serial/Package.swift"
grep -q 'PICO_SDK_PATH must point to the shared Pico SDK' "$tmp/serial/Firmware/CMakeLists.txt"
! grep -q 'Vendor/pico-sdk' "$tmp/serial/Firmware/CMakeLists.txt"
grep -Fq 'initialize_usb_interface_at_start' "$tmp/serial/swiftpico.json"
! grep -Fq 'pico_enable_stdio_usb(${PICOKIT_PRODUCT} 1)' "$tmp/serial/Firmware/CMakeLists.txt"
grep -q 'Serial.read()' "$tmp/serial/Sources/serial/main.swift"
grep -Fq 'Serial.write(byte)' "$tmp/serial/Sources/serial/main.swift"
grep -Fq 'Serial.println("Serial echo ready")' "$tmp/serial/Sources/serial/main.swift"
grep -Fq 'if !Serial.connected' "$tmp/serial/Sources/serial/main.swift"
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
perl -pi -e 's/"picoKitVersion"\s*:\s*"0\.2\.13"/"picoKitVersion" : "0.2.14"/' "$localKitProject/swiftpico.json"
staleLockOutput="$tmp/stale-lock.log"
if "$cli" dependencies generate --context "$localKitProject/swiftpico.json" >"$staleLockOutput" 2>&1; then
    echo "stale PicoKit lock unexpectedly regenerated" >&2
    exit 1
fi
grep -q 'stale for the configured local PicoKit checkout' "$staleLockOutput"

libraryProject="$tmp/libraries"
"$cli" init --board pico --name LibraryTest --template blink --path "$libraryProject" --skip-resolve
"$cli" add swift --context "$libraryProject/swiftpico.json" \
    --url https://github.com/example/EmbeddedMath.git --from 1.0.0 \
    --package EmbeddedMath --product EmbeddedMath --target EmbeddedMath --skip-resolve
grep -Fq '.package(name: "EmbeddedMath", url: "https://github.com/example/EmbeddedMath.git", exact: "1.0.0")' "$libraryProject/Package.swift"
grep -Fq '.product(name: "EmbeddedMath", package: "EmbeddedMath")' "$libraryProject/Package.swift"
grep -Fq '"integration" : "swiftSources"' "$libraryProject/Firmware/dependencies.json"
beforeInvalidPackage=$(shasum -a 256 "$libraryProject/Package.swift" "$libraryProject/Firmware/dependencies.json")
if "$cli" add swift --context "$libraryProject/swiftpico.json" \
    --url https://github.com/example/EmbeddedMath.git --from 1.0.0 \
    --package ../escape --product InvalidProduct --target InvalidProduct --skip-resolve >"$tmp/invalid-package.log" 2>&1; then
    echo "unsafe Swift package identity unexpectedly accepted" >&2
    exit 1
fi
test "$beforeInvalidPackage" = "$(shasum -a 256 "$libraryProject/Package.swift" "$libraryProject/Firmware/dependencies.json")"
"$cli" add swift --context "$libraryProject/swiftpico.json" \
    --url https://github.com/example/EmbeddedMath.git --from 1.0.0 \
    --package EmbeddedMath --product EmbeddedMathExtras --target EmbeddedMathExtras --skip-resolve
grep -Fq '.product(name: "EmbeddedMathExtras", package: "EmbeddedMath")' "$libraryProject/Package.swift"
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
grep -Fq '.package(name: "EmbeddedMath"' "$libraryProject/Package.swift"
grep -Fq 'EmbeddedMathExtras' "$libraryProject/Package.swift"
"$cli" dependencies remove EmbeddedMathExtras --context "$libraryProject/swiftpico.json"
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

rm -f "$flashProject/Firmware/dependencies.json"
toolchainOutput="$tmp/empty-toolchain.log"
if PICO_TOOLCHAIN_PATH= "$cli" build --context "$flashProject/swiftpico.json" >"$toolchainOutput" 2>&1; then
    echo "empty PICO_TOOLCHAIN_PATH unexpectedly accepted" >&2
    exit 1
fi
grep -q 'PICO_TOOLCHAIN_PATH is empty' "$toolchainOutput"

echo "SwiftPico CLI integration passed"
