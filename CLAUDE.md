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
- Accueil bento personnalisable : `HomeLayout.swift` (tuiles, ordre, taille, ce que dit chaque tuile),
  `HomeBentoView.swift`, `HomeBentoPacking.swift` (rangement + forme des jetons, logique pure),
  `HomeSettingsView.swift` (Réglages → Accueil). Oli sur le bureau : `DesktopOli.swift` + `DesktopOliHub.swift`
  (Fixe / Me suit / Se promène, bulles, panneau central au clic), `OliAutomations.swift` (actions en un clic,
  routines), `OneClickConnect.swift` (session du Mac ou page du service + jeton repris au presse-papiers).
  `DesktopTidy.swift` (« Ranger mon bureau » : déplace dans « Rangé par Oli », ne supprime jamais, annulable).
  `OliRules.swift` + `AutomationsIslandView.swift` (onglet ⚡ : règles « Quand… alors… » ; onglet ✨ `TidyIslandView` : où / quoi / comment ranger, aperçu, annuler).
  Réglage « Oli reste chez lui » (`DesktopOliController.staysHome`) : Oli ne quitte jamais l'encoche.
  Mails : `ImapClient.swift` (IMAP natif, lecture en PEEK, UID MOVE + COPYUID), `MailParsing.swift` (pur), `MailCenter.swift`
  (relève 5 min, tri Claude via `ClaudeService.runClaudeCode`, rangement dans « Oli/<Catégorie> », annuler) ; pages `MailAgendaViews.swift`
  (onglets ✉︎ `.inbox` et 📅 `.agenda`). Agenda en bento + `OculotAgenda.swift` : RPC `oculot_agenda_api` du site
  (lire, `rdv_prendre`, `ecrire`) avec le mot de passe de l'agenda gardé au Trousseau (`agenda-password`, `agenda-member`).
  Plusieurs boîtes : `MailAccounts.swift` (Trousseau `mail-extra-accounts`, mot de passe d'application repris au presse-papiers) ;
  `GoogleOAuth.swift` (« Se connecter avec Google » : PKCE + retour 127.0.0.1, XOAUTH2 IMAP ; client OAuth « Application de bureau »
  importé depuis ~/Downloads/client_secret_*.json vers le Trousseau `google-oauth-client`).
  `StarPower.swift` : mode étoile (arc-en-ciel + danse) sur nouveau rendez-vous ou mail d'Oculot ; `scripts/oli-desktop.sh star` (Debug).
  En-tête de l'encoche : 5 onglets à gauche de l'encoche physique, +, ⚡, ✨ à droite (pas de place pour plus).
  Tests : `scripts/test-home.sh`, `scripts/test-tidy.sh`, `scripts/test-mail.sh`, `scripts/test-imap.sh` (faux serveur local). Captures sans souris : `scripts/oli-desktop.sh hub|say|follow|wander|settings` (Debug).
- `OliAssistant/Widget/` — widget WidgetKit (lit l’instantané `Sources/Shared/OliWidgetSnapshot.swift` écrit par `WidgetSnapshotWriter.swift`).
- `android/` — app Android d’Oli (Kotlin + Compose) : Aujourd’hui, verrou biométrique, Connexions (espace,
  agenda Oculot, sites, Claude via jumelage QR avec le Mac `oli://pair` → `/v1/status`, `/v1/chat`),
  automatisations (briefing 8 h 30, rappels, pannes, échéances), partage, widget Glance, accueil bento, Oli flottant
  (`overlay/OverlayService.kt`), Claude Code (`/v1/claude/sessions`, `/v1/claude/approvals/<id>`), santé du téléphone
  (audit, nettoyage, rangement), défis/badges (DataStore), splash animé. Clair http autorisé
  globalement (Android ne filtre pas par IP) mais l’app ne parle en clair qu’à une IP locale (`MacLink.isLocalHost`). `JAVA_HOME=~/.local/jdk-17/Contents/Home ./gradlew assembleDebug testDebugUnitTest`
  (SDK dans `~/Library/Android/sdk`, chemin dans `android/local.properties`, non versionné).
- `docs/PLAN.md` — plan par phases. `tools/sounds-gen.py` — génère les sons.

## Construire
```
cd OliAssistant && xcodegen && xcodebuild -scheme Oli -configuration Debug -derivedDataPath ../.build -skipPackagePluginValidation build
```
SwiftTerm est épinglé en 1.11.2 (les versions suivantes exigent le Metal Toolchain).

## Règles
- Swift 6, concurrence stricte. Pas de dépendance tierce sauf indispensable (SwiftTerm l’est).
- Secrets dans le Trousseau uniquement. Aucune télémétrie.
- Toute nouvelle clé du Trousseau doit être ajoutée à `KeychainStore.allKeys` (ClaudeService.swift), sinon elle est oubliée au relancement.
- Ne jamais bloquer Claude Code : si l’app ne répond pas, le hook sort tout de suite.
- Ne jamais écraser `~/.claude/settings.json` : sauvegarde datée, fusion, diff, accord explicite.
- Ne jamais envoyer un mail ni accepter une autorisation sans clic explicite.
- 0 % CPU quand l’îlot est caché.
- Les identifiants de pastilles sont des contrats stables : ne jamais les renommer.
- Textes de l’interface en français, ton Oculot (chaleureux, direct, sans jargon).
