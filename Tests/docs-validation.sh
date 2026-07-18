#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
docs="$root/Docs"

for file in README.md getting-started.md examples.md project-anatomy.md \
    command-reference.md configuration.md external-libraries.md troubleshooting.md; do
    test -s "$docs/$file"
done

for link in getting-started.md examples.md project-anatomy.md command-reference.md \
    configuration.md external-libraries.md troubleshooting.md; do
    grep -Fq "($link)" "$docs/README.md"
done

source="$root/Sources/SwiftPicoCore"
for template in blink serial adc pwm i2c spi interrupt watchdog; do
    grep -Fq "\"$template\"" "$source/Templates.swift"
done

grep -Fq 'swiftpico flash --volume' "$docs/getting-started.md"
grep -Fq 'initialize_usb_interface_at_start' "$docs/configuration.md"
grep -Fq 'dependencies.lock' "$docs/external-libraries.md"
echo "SwiftPico documentation validation passed"
