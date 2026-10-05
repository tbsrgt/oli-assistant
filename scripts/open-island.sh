#!/usr/bin/env bash
# Build Debug uniquement : ouvre l'îlot d'Oli comme un survol ; « terminal » ouvre le terminal, « automations » l’onglet ⚡ (pour les captures).
OBJ="${1:-}"
exec swift -e "import Foundation; DistributedNotificationCenter.default().postNotificationName(.init(\"studio.oculot.oli.openIsland\"), object: \"$OBJ\", userInfo: nil, deliverImmediately: true)"
