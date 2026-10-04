# Oli, l'assistant Oculot dans l'encoche — plan par phases

Usage interne Oculot. Contraintes : tout gratuit, secrets dans le Trousseau, rien ne sort du Mac sauf vers les services
qu'on branche nous-mêmes.

## Phase 0 — Base (fait le 2026-10-04)
- Build Debug, installation dans ~/Applications/Oli.app.
- Mascotte V1 : corps crème, yeux encre, étoile tomate en pupille, palette d'états Oculot.
- Icône, barre de menu, nom « Oculot », tenue saisonnière désactivée, bouton de réduction.

## Phase 1 — Oli, mascotte finale (fait le 2026-10-04)
- Chara design retenu (image de référence archivée sur la page Figma « Oli · Chara design ») :
  étoile orange à quatre branches, visière noire brillante, deux yeux pilules crème lumineux,
  petit satellite orange en haut à droite. Pas de mains, pas de joues.
- Le satellite vit : flotte au repos, tourne autour d'Oli quand Claude réfléchit, pulse quand il
  attend un accord, devient beurre quand c'est terminé ; le badge d'état prend sa place.
- Quatre icônes d'app au choix dans Réglages → General (lumineuse, sombre, claire, contour).
- Sons Oculot : remplacer les 28 WAV (petits sons synthétiques courts, générés en local).
- Animation d'accueil au lancement refaite à la charte.
- Chat intégré : Oli se présente comme l'assistant d'Oculot, connaît l'équipe, les offres,
  le ton (on / vous, pas de jargon).
- Garde-robe réduite à ce qui a du sens (lunettes, bonnet) ou retirée.

## Phase 2 — Espace client dans l'encoche (code fait le 2026-10-04, déploiement en attente)
- Fait : route `GET /api/espace/summary` (jeton ESPACE_TEAM_TOKEN, lecture seule) dans nova-studio-espace ;
  côté Oli : EspacePoller (5 min), pastille « Espace client », liste + fiche dans l'îlot, alertes
  (échéance ≤ 7 j, inactif ≥ 7 j, nouveau client), bloc dans Réglages → Integrations.
- Lecteur d'Oli aligné sur le format réel de la route (étapes et petits mots en liste, jours restants calculés en local).
- Route poussée en PR tbsrgt/oculot#3, testée en local sur les données de prod.
- Reste : poser ESPACE_TEAM_TOKEN sur Vercel (~/.cache/oculot-espace/apply-team-token.sh), fusionner la PR #3,
  ranger le jeton dans le Trousseau pour Oli (service studio.oculot.oli, compte espace-token).
- Côté espace.oculot.studio : une route `/api/espace/summary` protégée par un jeton d'équipe,
  qui renvoie les clients actifs, leurs étapes, la date visée, la dernière activité.
- Côté Oli : pastille « Espace » (couleur tomate), poller toutes les 5 min.
  - Vue : liste des projets, étape en cours, jours restants, dernier mot envoyé au client.
  - Alertes : échéance à moins de 7 jours, client sans activité depuis 7 jours, nouveau client créé.
  - Clic : ouvre la fiche admin du client.
- Plus tard : envoyer un « petit mot » au client depuis le chat d'Oli.

## Phase 3 — Agenda (≈ 1 j)
- Lecture seule d'abord, sans OAuth : l'adresse iCal secrète de l'agenda Google Oculot,
  relue toutes les 5 min.
  - Prochain rendez-vous dans l'en-tête de l'encoche, Oli prévient 10 min avant.
  - Vue journée au clic, lien vers la visio ou l'adresse.
- Ensuite, si utile : écriture via l'API Google Calendar (OAuth) pour que le chat crée un rendez-vous.
- Cal.com est déjà intégré dans l'app si on l'adopte pour les prises de rendez-vous prospects.

## Phase 4 — Surveillance des sites clients (fait le 2026-10-04)
- Fait : toutes les 10 min, HTTP, latence et certificat des sites livrés de l'espace + liste manuelle
  (SiteCheck.swift, SitesPoller.swift) ; chaque jour, score PageSpeed mobile (clé gratuite à mettre dans
  Réglages, sinon quota 429), expiration du domaine par RDAP, www/domaine nu ; chaque semaine, robots.txt,
  sitemap.xml et liens internes de l'accueil (SiteAudit.swift). Alerte une fois par nouveau problème.
  Bouton « Corriger avec Claude Code » : ouvre Terminal + claude dans le clone local du dépôt du client
  (repo de l'espace), sinon le dépôt sur GitHub. Tests : scripts/test-sites.sh.
- Pas fait : test du formulaire de contact (on n'envoie jamais de formulaire), Oli « inquiet » au-delà
  de l'état erreur existant.
- Source : `live_url` et `preview_url` de l'espace client, plus une liste manuelle.
- Toutes les 10 min : site joignable, code HTTP, temps de réponse, certificat HTTPS (expiration),
  redirection www/apex.
- Une fois par jour : Lighthouse via l'API PageSpeed (gratuite), domaine OVH qui expire
  (clé API déjà en place), formulaire de contact qui répond.
- Une fois par semaine : liens cassés, sitemap, robots (réutilise la logique du plugin
  livraison-site:verifier).
- Dans l'encoche : pastille « Sites », Oli passe en tomate et prend l'air inquiet si un site tombe.
  Clic : rapport, et bouton « Corriger avec Claude Code » qui ouvre le bon dépôt.

## Phase 5 — Réseaux sociaux (5a Instagram codé le 2026-10-04, en attente du jeton)
- Fait : lecture Instagram toutes les 30 min (Social.swift, SocialPoller.swift) avec un jeton « Instagram
  Login » (IGAA…, le plus simple) ou « Facebook Login » (EAA…, compte pro relié à une page) : abonnés,
  12 derniers posts, commentaires sans réponse des 14 derniers jours, rappel après 6 jours sans post.
  Pastille « Instagram » (à activer dans Active pills), bloc Réglages, briefing, récap, contexte du chat.
  Testé sur réponses d'exemple (scripts/test-social.sh) et contre l'API réelle avec un faux jeton.
- Reste : coller un vrai jeton ; LinkedIn ; 5b (posts proposés à valider) ; 5c (publication via planificateur).
Instagram (oculot.studio) et LinkedIn (company/oculot-studio).
- 5a Lire : abonnés, derniers posts, commentaires et messages à traiter.
  Instagram : API Graph (compte pro relié à une page Facebook, jeton longue durée).
  LinkedIn : l'API page entreprise demande une validation Marketing, sinon lecture limitée.
- 5b Préparer : Oli propose des posts (reprend le moteur de visuels com-visuels), tu valides
  dans l'encoche comme une permission Claude Code.
- 5c Publier : via un planificateur gratuit avec API (Postiz auto-hébergé, ou n8n) plutôt que
  les API natives, pour éviter les validations Meta et LinkedIn.
Rappels : « pas de post depuis 6 jours », « 3 commentaires sans réponse ».

## Phase 6 — Vraiment notre assistant (fait le 2026-10-04, sauf agenda et réseaux)
- Fait : briefing du matin au premier survol entre 5 h et 13 h (projets en retard, échéances de la semaine,
  projets inactifs, nouveaux clients, sites en panne ou à surveiller) et récap du vendredi dès 15 h
  (étapes bouclées, projets terminés, nouveaux clients, échéances à venir, pannes de la semaine), écrits en
  local sans IA (Briefing.swift, BriefingCenter.swift, tests scripts/test-briefing.sh).
- Chat : état d'Oculot en direct dans le prompt système (tous fournisseurs) ; outils espace_projets,
  etat_sites, verifier_sites, ouvrir_fiche_client avec l'API Claude (clé Anthropic à mettre dans Réglages).
- Raccourcis : ⌃⌥E ouvre l'admin de l'espace, ⌃⌥S vérifie les sites tout de suite.
- Alarme de panne : triple son fort, Oli rouge et paniqué, encoche ouverte sur le problème.
- Reste : agenda (phase 3, mise de côté) et réseaux (phase 5) dans le briefing ; « créer un client » en raccourci.
- Briefing du matin au premier survol : rendez-vous du jour, clients en retard, sites en panne,
  posts à publier.
- Chat avec outils : Oli interroge l'espace, l'agenda, les sites et les réseaux depuis la
  conversation (tool use de l'API Claude), au lieu de répondre de mémoire.
- Raccourcis globaux : ouvrir l'espace admin, lancer un audit de site, créer un client.
- Récap hebdo le vendredi.

## Décisions à prendre
1. Nom de la mascotte : « Oli » (provisoire) ou autre.
2. Agenda : Google Calendar du compte Oculot (lequel ?) ou Cal.com.
3. Réseaux : commencer par Instagram ou LinkedIn.
