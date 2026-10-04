# Oli Assistant — guide pour les agents

App macOS (Swift 6, SwiftUI + AppKit) qui vit dans l’encoche : l’assistant d’Oculot Studio.

## Organisation (`Oli/Sources/`)
- `App/` — point d’entrée, barre des menus, raccourcis globaux, déclencheurs Debug.
- `Core/` — `OliModel` (état unique), `Secrets` (Trousseau), `Theme` (charte), `Chimes` (sons
  synthétisés), `BriefingDesk`.
- `Notch/` — fenêtre de l’encoche (pliée / dépliée), rail, en-têtes.
- `Mascot/` — Oli dessiné en Canvas, humeurs calme / travail / attente / content / alarme.
- `Sections/` — Aujourd’hui, Claude Code, Projets, Sites, Agenda, Instagram ; composants communs.
- `Claude/` — pont HTTP local, sessions, installation des hooks.
- `Engines/` — moteurs purs et testables (sites, audits, espace, agenda, Instagram, briefing).
- `Watchers/` — rafraîchissements périodiques et alertes.
- `Terminal/`, `Chat/`, `Settings/`.

## Construire
```
cd Oli && xcodegen && xcodebuild -scheme Oli -configuration Debug -derivedDataPath ../.build -skipPackagePluginValidation build
```
Le `.xcodeproj` est généré (ignoré par git). SwiftTerm épinglé en 1.11.2 (pas de Metal Toolchain).

## Règles
- Concurrence stricte Swift 6. Une seule dépendance : SwiftTerm.
- Secrets dans le Trousseau uniquement. Aucune télémétrie.
- Le relais des hooks ne bloque jamais Claude Code.
- `~/.claude/settings.json` : copie datée, aperçu, écriture seulement après un clic.
- Jamais d’envoi, de publication ou d’autorisation sans clic explicite.
- Rien ne tourne quand l’encoche est repliée et calme.
- Interface en français, ton Oculot ; charte : Bricolage Grotesque, tomate, beurre.
