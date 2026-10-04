#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/oli-shortcuts.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc OliAssistant/Sources/App/ShortcutLogic.swift \
    tests/ShortcutTests.swift -o "$TEST_DIR/shortcut-tests"
"$TEST_DIR/shortcut-tests"
