#!/usr/bin/env bash
# « Oli range ton bureau » : catégories, homonymes, annulation, sur un faux bureau temporaire.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/oli-tidy.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete \
    OliAssistant/Sources/App/DesktopTidy.swift tests/DesktopTidyTests.swift -o "$TEST_DIR/test-tidy"
"$TEST_DIR/test-tidy"
