# Oli Assistant — guide pour les agents

App macOS native (`OliAssistant/`, Swift 6, SwiftUI + AppKit) : Oli, la mascotte d’Oculot Studio,
vit dans l’encoche du MacBook et affiche l’état du studio (Claude Code, espace client, sites,
agenda, Instagram), avec un terminal intégré.

## Où sont les choses
- `OliAssistant/Sources/App/` — tout le code Swift. `OliAssistant/Resources/sounds/` — les sons.
- `OliAssistant/project.yml` — projet XcodeGen (ne jamais éditer le `.xcodeproj`, il est généré).
- `OliAssistant/Sources/App/PillCatalog.swift` — catalogue des pastilles (identifiants stables).
- Moteurs Oculot : `SiteCheck.swift` / `SiteAudit.swift` / `SitesPoller.swift` (sites),
  `EspacePoller.swift` (espace client), `AgendaICS.swift` / `AgendaPoller.swift` (agenda),
  `Social.swift` / `SocialPoller.swift` (Instagram), `Briefing.swift` / `BriefingCenter.swift`,
  `OculotHomeView.swift` (accueil), `OliTerminal.swift` (terminal SwiftTerm).
- `OliAssistant/Widget/` — widget WidgetKit (lit l’instantané `Sources/Shared/OliWidgetSnapshot.swift` écrit par `WidgetSnapshotWriter.swift`).
- `docs/PLAN.md` — plan par phases. `tools/sounds-gen.py` — génère les sons.

## Construire
```
cd OliAssistant && xcodegen && xcodebuild -scheme Oli -configuration Debug -derivedDataPath ../.build -skipPackagePluginValidation build
```
SwiftTerm est épinglé en 1.11.2 (les versions suivantes exigent le Metal Toolchain).

## Règles
- Swift 6, concurrence stricte. Pas de dépendance tierce sauf indispensable (SwiftTerm l’est).
- Secrets dans le Trousseau uniquement. Aucune télémétrie.
- Ne jamais bloquer Claude Code : si l’app ne répond pas, le hook sort tout de suite.
- Ne jamais écraser `~/.claude/settings.json` : sauvegarde datée, fusion, diff, accord explicite.
- Ne jamais envoyer un mail ni accepter une autorisation sans clic explicite.
- 0 % CPU quand l’îlot est caché.
- Les identifiants de pastilles sont des contrats stables : ne jamais les renommer.
- Textes de l’interface en français, ton Oculot (chaleureux, direct, sans jargon).
