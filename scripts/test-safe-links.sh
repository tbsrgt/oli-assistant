#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/oli-safe-links.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc OliAssistant/Sources/App/SafeWebURL.swift \
    tests/SafeWebURLTests.swift -o "$TEST_DIR/safe-links-tests"
"$TEST_DIR/safe-links-tests"
