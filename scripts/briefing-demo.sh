#!/usr/bin/env bash
# Build Debug uniquement : affiche le briefing du matin (ou « friday » : le récap) tout de suite.
KIND="${1:-morning}"
exec swift -e "import Foundation; DistributedNotificationCenter.default().postNotificationName(.init(\"studio.oculot.oli.briefingDemo\"), object: \"$KIND\", userInfo: nil, deliverImmediately: true)"
