#!/usr/bin/env bash
# Vérifie quelques sites réels avec le moteur de surveillance (SiteCheck.swift).
# Usage : scripts/test-sites.sh [url …]   (défaut : oculot.studio, espace.oculot.studio, example.invalid)
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/oli-sites.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete \
    Oli/Sources/Engines/SiteCheck.swift Oli/Sources/Engines/SiteAudit.swift scripts/test-sites.swift -o "$TEST_DIR/test-sites"
"$TEST_DIR/test-sites" "$@"
