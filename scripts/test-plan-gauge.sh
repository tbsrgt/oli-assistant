#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/oli-plan-gauge.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc OliAssistant/Sources/App/ClaudePlanGauge.swift \
    tests/ClaudePlanGaugeTests.swift -o "$TEST_DIR/plan-gauge-tests"
"$TEST_DIR/plan-gauge-tests"
