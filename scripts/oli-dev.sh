#!/usr/bin/env bash
# Build Debug uniquement : pilote Oli pour les essais et les captures.
#   scripts/oli-dev.sh open [home|claude|terminal|projects|sites|agenda|instagram|chat]
#   scripts/oli-dev.sh fold | panne | briefing [friday] | flash "texte"
CMD="$*"
exec swift -e "import Foundation; DistributedNotificationCenter.default().postNotificationName(.init(\"studio.oculot.oli.dev\"), object: \"$CMD\", userInfo: nil, deliverImmediately: true)"
