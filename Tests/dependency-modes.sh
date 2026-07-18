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

for name in CMakeLibrary SourceLibrary HeaderLibrary CPPLibrary; do
    repository="$tmp/$name"
    mkdir -p "$repository"
    cp -R "$root/Tests/Fixtures/DependencyModes/$name/." "$repository/"
    git -C "$repository" init -q
    git -C "$repository" add .
    git -C "$repository" -c user.name=SwiftPico -c user.email=tests@swiftpico.invalid commit -qm initial
done

local_repository="$tmp/LocalLibrary"
mkdir -p "$local_repository"
cp -R "$root/Tests/Fixtures/DependencyModes/LocalLibrary/." "$local_repository/"

archive_repository="$tmp/ArchiveLibrary"
mkdir -p "$archive_repository"
cp -R "$root/Tests/Fixtures/DependencyModes/ArchiveLibrary/." "$archive_repository/"
archive="$tmp/archive-fixture.tar.gz"
tar -czf "$archive" -C "$archive_repository" .
archive_sha256=$(shasum -a 256 "$archive" | awk '{print $1}')

project="$tmp/DependencyModes"
"$cli" init --board pico --name DependencyModes --template blink \
    --path "$project" --skip-resolve --pico-kit-path "$kit"
cp "$root/Tests/Fixtures/DependencyModes/dependencies.json" "$project/Firmware/dependencies.json"
cp "$root/Tests/Fixtures/DependencyModes/AppInterop.h" "$project/Firmware/Interop/AppInterop.h"
cp "$root/Tests/Fixtures/DependencyModes/AppInterop.c" "$project/Firmware/Interop/AppInterop.c"
cp "$root/Tests/Fixtures/DependencyModes/CppAdapter.cpp" "$project/Firmware/Interop/CppAdapter.cpp"
cp "$root/Tests/Fixtures/DependencyModes/main.swift" "$project/Sources/DependencyModes/main.swift"

sed -i '' \
    -e "s|__CMAKE_REPOSITORY__|$tmp/CMakeLibrary|g" \
    -e "s|__SOURCE_REPOSITORY__|$tmp/SourceLibrary|g" \
    -e "s|__HEADER_REPOSITORY__|$tmp/HeaderLibrary|g" \
    -e "s|__CPP_REPOSITORY__|$tmp/CPPLibrary|g" \
    -e "s|__LOCAL_REPOSITORY__|$local_repository|g" \
    -e "s|__ARCHIVE_URL__|file://$archive|g" \
    -e "s|__ARCHIVE_SHA256__|$archive_sha256|g" \
    "$project/Firmware/dependencies.json"

"$cli" dependencies resolve --context "$project/swiftpico.json"
grep -q 'exactCommit' "$project/Firmware/dependencies.lock"
grep -q 'FetchContent_MakeAvailable(cmake_fixture)' "$project/Firmware/Generated/Dependencies.cmake"
grep -q 'module MockCMake' "$project/Firmware/Generated/Dependencies.cmake"
grep -q 'add_library(source_fixture STATIC' "$project/Firmware/Generated/Dependencies.cmake"
grep -q 'add_library(header_fixture INTERFACE)' "$project/Firmware/Generated/Dependencies.cmake"
grep -q -- '-fno-exceptions -fno-rtti' "$project/Firmware/Generated/Dependencies.cmake"
grep -q 'SOURCE_DIR "' "$project/Firmware/Generated/Dependencies.cmake"
grep -q 'URL_HASH SHA256=' "$project/Firmware/Generated/Dependencies.cmake"
grep -q 'set(MOCK_CMAKE_OPTION "ON" CACHE STRING' "$project/Firmware/Generated/Dependencies.cmake"

first_lock=$(shasum -a 256 "$project/Firmware/dependencies.lock" | awk '{print $1}')
cp "$tmp/SourceLibrary/source_only_v2.c" "$tmp/SourceLibrary/source_only.c"
git -C "$tmp/SourceLibrary" add source_only.c
git -C "$tmp/SourceLibrary" -c user.name=SwiftPico -c user.email=tests@swiftpico.invalid commit -qm second
second_commit=$(git -C "$tmp/SourceLibrary" rev-parse HEAD)

"$cli" dependencies generate --context "$project/swiftpico.json"
test "$first_lock" = "$(shasum -a 256 "$project/Firmware/dependencies.lock" | awk '{print $1}')"
"$cli" dependencies update source_fixture --revision "$second_commit" --context "$project/swiftpico.json"
"$cli" dependencies resolve --context "$project/swiftpico.json"
grep -q "$second_commit" "$project/Firmware/dependencies.lock"

if [ -z "${SWIFTPICO_VALIDATE_ONLY:-}" ]; then
    "$cli" build --configuration release --context "$project/swiftpico.json"
    test -f "$project/Firmware/build/DependencyModes.uf2"
fi
echo "SwiftPico dependency integration modes passed"
