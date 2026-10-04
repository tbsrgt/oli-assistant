#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/oli-github-activity.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc OliAssistant/Sources/App/GitHubActivity.swift \
    tests/GitHubActivityTests.swift -o "$TEST_DIR/github-activity-tests"
"$TEST_DIR/github-activity-tests"
