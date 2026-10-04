#!/usr/bin/env bash
# Tests du parseur iCal de l'agenda Oculot (AgendaICS.swift, Foundation seul).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/oculot-ics.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -strict-concurrency=complete OliAssistant/Sources/App/AgendaICS.swift \
    tests/AgendaICSTests.swift -o "$TEST_DIR/ics-tests"
"$TEST_DIR/ics-tests"
