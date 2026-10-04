#!/usr/bin/env bash
# Compile Oli, le signe et l'installe dans ~/Applications/Oli Assistant.app.
# Avec le certificat « Oli Dev » (Trousseau d'accès → Assistant de certification → Créer un
# certificat, type « Signature de code »), la signature reste la même d'une version à l'autre :
# le Trousseau ne redemande plus le mot de passe à chaque mise à jour.
set -euo pipefail
cd "$(dirname "$0")/../OliAssistant"
~/.local/bin/xcodegen >/dev/null
xcodebuild -scheme Oli -configuration Debug -derivedDataPath ../.build -skipPackagePluginValidation build 2>&1 \
  | grep -E 'error:|BUILD (SUCCEEDED|FAILED)' | sort -u
APP=../.build/Build/Products/Debug/Oli.app
if security find-identity -p codesigning 2>/dev/null | grep -q '"Oli Dev"'; then
  # Le widget d'abord (avec ses droits sandbox), puis l'app — jamais codesign --deep.
  codesign --force -s "Oli Dev" --entitlements Widget/OliWidget.entitlements "$APP/Contents/PlugIns/OliWidget.appex"
  codesign --force -s "Oli Dev" --entitlements Resources/Oli.entitlements "$APP"
  echo "Signé avec « Oli Dev » (signature stable)."
else
  echo "Certificat « Oli Dev » introuvable : signature ad hoc (le Trousseau redemandera après chaque mise à jour)."
fi
pkill -f "Oli Assistant.app/Contents/MacOS/Oli" 2>/dev/null || true
sleep 1
rm -rf ~/Applications/"Oli Assistant.app"
cp -R "$APP" ~/Applications/"Oli Assistant.app"
open ~/Applications/"Oli Assistant.app"
echo "Oli installé."
