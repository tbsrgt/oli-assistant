# Oli Assistant

L’assistant d’Oculot Studio, dans l’encoche du Mac. Oli est une petite étoile orange qui tient le
studio au courant, ouvre un terminal sous la main et laisse piloter Claude Code sans quitter ce
qu’on fait.

## Ce qu’il fait

- **Aujourd’hui** : l’essentiel du studio, le plus urgent d’abord (autorisations Claude Code,
  pannes, retards, rendez-vous, projets, sites, Instagram), et chaque matin « le mot d’Oli ».
  Le vendredi après-midi, le récap de la semaine.
- **Claude Code** : toutes les sessions (Terminal, iTerm, VS Code, le terminal d’Oli), ce qu’elles
  font, et les autorisations à accepter ou refuser d’un clic depuis l’encoche.
- **Terminal** : de vrais shells en onglets ; « Claude Code » sur un projet ouvre son dépôt et
  lance Claude directement.
- **Projets** : l’espace client (espace.oculot.studio) — étapes, échéances, dernier mot au client.
- **Sites** : toutes les 10 min (HTTP, temps de réponse, certificat), chaque jour (PageSpeed,
  expiration du domaine, www / domaine nu), chaque semaine (robots, sitemap, liens cassés).
  Une panne : alarme, Oli rouge et paniqué, encoche ouverte sur le site.
- **Agenda** (agenda.oculot.studio ou Google, lien iCal) : prochain rendez-vous, alerte 10 min avant.
- **Instagram** (lecture seule) : abonnés, derniers posts, commentaires sans réponse.
- **Demander à Oli** : un chat Claude qui connaît l’état du studio et peut agir (vérifier les
  sites, ouvrir le dépôt d’un client).

Seules les sections branchées apparaissent. Replié, Oli est invisible quand tout est calme.

## Raccourcis

| Touches | Action |
|---|---|
| ⌥⌘O | Ouvrir / replier Oli |
| ⌥⌘T | Terminal |
| ⌥⌘J | Demander à Oli |
| Échap | Replier (hors terminal) |

## Construire

Prérequis : Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```
cd Oli
xcodegen
xcodebuild -scheme Oli -configuration Debug -derivedDataPath ../.build -skipPackagePluginValidation build
codesign --force --deep -s - ../.build/Build/Products/Debug/Oli.app
```

## Tests

```
scripts/test-bridge.sh     # pont Claude Code, installation des hooks, espace client
scripts/test-sites.sh      # surveillance des sites (réseau réel)
scripts/test-briefing.sh   # briefing et récap
scripts/test-social.sh     # Instagram
scripts/test-ics.sh        # agenda iCal
```

En Debug, `scripts/oli-dev.sh` pilote l’app (open <section>, panne, briefing, allow…).

## Claude Code

Réglages → Claude Code → Installer. Oli montre chaque changement de `~/.claude/settings.json`
avant d’écrire et garde une copie datée. Le relais (`~/.claude/oli/oli-hook`) envoie les
événements à Oli en local ; si Oli n’est pas lancé, il sort aussitôt sans rien bloquer.

## Secrets

Tous les jetons vivent dans le Trousseau (service `studio.oculot.oli`), jamais sur le disque ni
dans git. Aucune télémétrie.

## Licence

© Oculot Studio, tous droits réservés. Composants tiers : `THIRD-PARTY.md`.
