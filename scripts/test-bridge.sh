#!/usr/bin/env bash
# Pont Claude Code et espace client.
set -euo pipefail
cd "$(dirname "$0")/.."
T="$(mktemp -d "${TMPDIR:-/tmp}/oli-bridge.XXXXXX")"; trap 'rm -rf "$T"' EXIT
swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete \
  Oli/Sources/Claude/HTTPRequest.swift Oli/Sources/Claude/HookInstaller.swift Oli/Sources/Engines/Espace.swift \
  tests/BridgeTests.swift -o "$T/t"
"$T/t"
