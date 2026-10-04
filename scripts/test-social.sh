#!/usr/bin/env bash
# Lecture Instagram d'Oli (Social.swift) sur des réponses d'exemple.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/oli-social.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete \
    Oli/Sources/Engines/Social.swift scripts/test-social.swift -o "$TEST_DIR/test-social"
"$TEST_DIR/test-social"
