#!/usr/bin/env bash
# Client IMAP d'Oli contre un faux serveur local : blocs {n}, non lus, déplacement, mot de passe refusé.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/oli-imap.XXXXXX")"
SERVER_PID=""
trap 'rm -rf "$TEST_DIR"; [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true' EXIT
python3 tests/fake_imap.py "$TEST_DIR/port" & SERVER_PID=$!
for _ in $(seq 50); do [ -s "$TEST_DIR/port" ] && break; sleep 0.1; done
swiftc -parse-as-library -swift-version 6 \
    OliAssistant/Sources/App/MailParsing.swift OliAssistant/Sources/App/ImapClient.swift \
    tests/ImapClientTests.swift -o "$TEST_DIR/test-imap"
"$TEST_DIR/test-imap" "$(cat "$TEST_DIR/port")"
