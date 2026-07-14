#!/bin/sh
set -eu
printf '%s\n' "$@" >> "$SWIFTPICO_TEST_LOG"
