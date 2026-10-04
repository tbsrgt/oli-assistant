# Oli Assistant

L’assistant d’Oculot Studio, dans l’encoche du Mac. Oli est une petite étoile orange qui tient
le studio au courant sans qu’on ait à ouvrir dix onglets.

## Ce qu’il fait

- **Accueil Oculot** : à l’ouverture, l’essentiel du studio en un coup d’œil (sites, projets,
  agenda, Instagram), le plus urgent en premier.
- **Terminal** : un vrai terminal macOS (zsh, couleurs, Claude Code, vim) dans l’encoche.
  Le shell continue de tourner quand l’encoche est repliée.
- **Claude Code** : les sessions lancées dans Terminal, iTerm, VS Code ou le terminal d’Oli
  s’affichent sur la pastille Claude Code ; les autorisations se donnent depuis l’encoche.
- **Espace client** (espace.oculot.studio) : projets, étapes, échéances, alertes.
- **Sites clients** : toutes les 10 min (HTTP, temps de réponse, certificat), chaque jour
  (PageSpeed, expiration du domaine, www / domaine nu), chaque semaine (robots, sitemap,
  liens cassés). Une panne : son fort, Oli rouge et paniqué, encoche ouverte sur le problème.
- **Agenda** (agenda.oculot.studio ou Google, lien iCal) : prochain rendez-vous, alerte 10 min avant.
- **Instagram** (lecture seule) : abonnés, derniers posts, commentaires sans réponse.
- **Briefing du matin et récap du vendredi**, écrits en local, sans IA.
- **Chat IA** avec l’état d’Oculot en direct (outils avec une clé Anthropic).

Seules les pastilles branchées (clé, jeton ou lien renseigné) apparaissent.

## Construire

Prérequis : Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```
cd OliAssistant
xcodegen
xcodebuild -scheme Oli -configuration Debug -derivedDataPath ../.build -skipPackagePluginValidation build
```

L’app est dans `.build/Build/Products/Debug/Oli.app`, déjà signée ad hoc par Xcode (l’app et son
widget). Ne pas la re-signer avec `codesign --deep` : ça effacerait les droits du widget (sandbox),
et WidgetKit l’ignorerait. S’il faut re-signer à la main, le widget d’abord, puis l’app :

```
APP=.build/Build/Products/Debug/Oli.app
codesign --force -s - --entitlements OliAssistant/Widget/OliWidget.entitlements "$APP/Contents/PlugIns/OliWidget.appex"
codesign --force -s - --entitlements OliAssistant/Resources/Oli.entitlements "$APP"
```

## Widget

`OliAssistant/Widget/` : widget WidgetKit (petit et moyen) pour le bureau et le Centre de
notifications. L’app écrit un instantané `~/Library/Application Support/Oli/widget/snapshot.json`
(sites, prochain projet, prochains rendez-vous) ; le widget, sandboxé, n’a le droit de lire que ce
dossier (exception de sandbox en lecture seule : pas besoin d’App Group ni d’équipe Apple). Un clic
ouvre `oli://`, qui déplie l’encoche. Le widget apparaît dans la galerie une fois l’app lancée
depuis son emplacement définitif.

## Tests

Chaque moteur se teste seul, sans lancer l’app :

```
scripts/test-sites.sh      # surveillance des sites (réseau réel)
scripts/test-briefing.sh   # briefing et récap
scripts/test-social.sh     # lecture Instagram
scripts/test-ics.sh        # agenda iCal
```

En build Debug, des démos : `scripts/sites-demo.sh` (panne), `scripts/briefing-demo.sh [friday]`,
`scripts/open-island.sh [terminal]`.

## Réglages et secrets

Tout se règle dans Réglages → Integrations. Les secrets vivent dans le Trousseau macOS
(service `studio.oculot.oli`), jamais sur le disque ni dans git. Aucune télémétrie : Oli ne parle
qu’aux services qu’on branche.

## Licence

Code sous licence MIT (voir `LICENSE`). Le terminal utilise
[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (MIT).
