#!/usr/bin/env bash
# Build Debug uniquement : pilote Oli sur le bureau pour les captures, sans souris ni clavier.
# hub | close | say | follow | wander | still | star | home | settings (Réglages → Accueil)
OBJ="${1:-hub}"
exec swift -e "import Foundation; DistributedNotificationCenter.default().postNotificationName(.init(\"studio.oculot.oli.desktop\"), object: \"$OBJ\", userInfo: nil, deliverImmediately: true)"
