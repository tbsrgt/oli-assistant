#!/usr/bin/env bash
# Build Debug uniquement : demande à Oli une passe de surveillance des sites tout de suite.
exec swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(.init("studio.oculot.oli.sitesCheckNow"), object: nil, userInfo: nil, deliverImmediately: true)'
