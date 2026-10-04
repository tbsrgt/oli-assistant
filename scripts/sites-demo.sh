#!/usr/bin/env bash
# Build Debug uniquement : simule la panne d'un « Site de démo » pour voir l'alerte d'Oli.
exec swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(.init("studio.oculot.oli.sitesDemoDown"), object: nil, userInfo: nil, deliverImmediately: true)'
