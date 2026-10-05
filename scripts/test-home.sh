#!/usr/bin/env bash
# Accueil bento (rangement), mouvement d'Oli sur le bureau, forme des jetons de connexion.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/oli-home.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete \
    OliAssistant/Sources/App/HomeBentoPacking.swift OliAssistant/Sources/App/DesktopOliLogic.swift \
    tests/HomeTests.swift -o "$TEST_DIR/test-home"
"$TEST_DIR/test-home"
