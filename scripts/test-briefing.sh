#!/usr/bin/env bash
# Textes du briefing du matin et du récap du vendredi (Briefing.swift).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/oli-briefing.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete \
    OliAssistant/Sources/App/Briefing.swift scripts/test-briefing.swift -o "$TEST_DIR/test-briefing"
"$TEST_DIR/test-briefing"
