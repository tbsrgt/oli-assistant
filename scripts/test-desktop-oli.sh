#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/oli-desktop.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc OliAssistant/Sources/App/DesktopOliLogic.swift \
    tests/DesktopOliTests.swift -o "$TEST_DIR/desktop-oli-tests"
"$TEST_DIR/desktop-oli-tests"
