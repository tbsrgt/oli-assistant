#!/usr/bin/env bash
# Build Debug uniquement : envoie une question au chat d'Oli, comme si on la tapait.
Q="${1:-Bonjour Oli}"
exec swift -e "import Foundation; DistributedNotificationCenter.default().postNotificationName(.init(\"studio.oculot.oli.chatDemo\"), object: \"$Q\", userInfo: nil, deliverImmediately: true)"
