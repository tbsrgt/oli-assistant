#!/usr/bin/env bash
# Lecture et tri des mails : en-têtes, extraits, réponses IMAP, premier tri, réponse de Claude.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/oli-mail.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete \
    OliAssistant/Sources/App/MailParsing.swift tests/MailTests.swift -o "$TEST_DIR/test-mail"
"$TEST_DIR/test-mail"
