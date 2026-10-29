# ADO Menu Bar Notifier — Refinement

## Contexte & objectif
Développeur sur Azure DevOps doit ouvrir le navigateur pour voir PRs à relire, retours sur ses PRs et work items assignés. Perte de réactivité, notifications email bruitées.
App macOS native, icône barre de menus : vue rapide PRs + work items, changement statut WI en un clic, notifications système sur événements pertinents.
Usage personnel, un seul utilisateur, authentification par PAT.

## Acteurs
- **Utilisateur** (propriétaire du PAT) : configure org/projets/PAT, consulte listes, change statut WI, reçoit notifications.
- **Azure DevOps** (système) : source des données, interrogé périodiquement (polling) via REST + PAT.

## Cas d'usage

### UC1 — Configuration initiale
- **Acteur** : Utilisateur
- **Préconditions** : app lancée, aucune config.
- **Scénario nominal** :
  1. Clic icône → message « Not configured » + bouton Settings.
  2. Saisie URL org (`https://dev.azure.com/<org>`) + PAT.
  3. App valide PAT (appel test) et récupère identité utilisateur.
  4. App liste projets de l'org → utilisateur coche projets suivis.
  5. App propose « Launch at login » (case cochée par défaut).
  6. Enregistrement. PAT stocké de façon sécurisée (jamais en clair sur disque). Lancement au démarrage activé si coché.
  7. Premier rafraîchissement.
- **Variantes / erreurs** :
  - PAT invalide / expiré / scopes insuffisants → message explicite, pas d'enregistrement.
  - URL org invalide / réseau KO → message explicite.
  - Aucun projet coché → enregistrement refusé.
- **Postconditions** : config persistée, polling actif.

### UC2 — Consulter PRs
- **Acteur** : Utilisateur
- **Préconditions** : configuré.
- **Scénario nominal** :
  1. Clic icône → panneau.
  2. Section « To Review » : PRs actives (projets suivis) où utilisateur = reviewer direct (nominatif).
  3. Section « My PRs » : PRs actives créées par utilisateur.
  4. Chaque ligne : titre, repo, auteur (À relire) ou état votes (Mes PRs), ancienneté, indicateur draft.
  5. Clic ligne → ouvre PR dans navigateur par défaut.
- **Variantes / erreurs** : section vide → état vide explicite. Erreur réseau → dernière donnée connue + bandeau erreur + heure dernière synchro.
- **Postconditions** : aucune.

### UC3 — Consulter work items assignés
- **Acteur** : Utilisateur
- **Préconditions** : configuré.
- **Scénario nominal** :
  1. Section « Work Items » : WI assignés à l'utilisateur, projets suivis, état hors catégories ADO `Completed` / `Removed` (indépendant du process : Agile, Scrum, Basic, custom).
  2. Ligne : ID, type, titre, état courant.
  3. Clic ligne → ouvre WI dans navigateur.
- **Variantes / erreurs** : idem UC2.

### UC4 — Changer statut work item
- **Acteur** : Utilisateur
- **Préconditions** : WI affiché.
- **Scénario nominal** :
  1. Action statut sur ligne WI → liste des états **définis dans ADO pour le type de ce WI** (dans son projet), moins états masqués (UC10), moins état courant.
  2. Choix état → mise à jour envoyée à ADO.
  3. Ligne mise à jour ; si état catégorie `Completed` / `Removed`, WI disparaît de liste au prochain refresh.
- **Variantes / erreurs** :
  - ADO refuse transition (règle de transition, champ obligatoire) → message d'erreur ADO affiché, état inchangé.
  - Réseau KO → erreur, état inchangé.
  - Tous états masqués → menu statut affiche « No state available ».
- **Postconditions** : état WI modifié dans ADO.

### UC5 — Notification nouveau WI assigné
- **Déclencheur** : WI apparaît dans liste assignés alors qu'absent au cycle précédent.
- **Résultat** : notification système « Work item assigned: #ID title ». Clic → ouvre WI.

### UC6 — Notification nouvelle PR à relire
- **Déclencheur** : PR apparaît dans « To Review » alors qu'absente au cycle précédent.
- **Résultat** : notification « Review requested: title (repo) by author ». Clic → ouvre PR.

### UC7 — Notification activité sur mes PRs
- **Déclencheurs** (auteur ≠ utilisateur, threads système exclus) :
  - nouveau thread de commentaire sur une de mes PRs ;
  - nouvelle réponse dans thread existant de mes PRs ;
  - changement de vote d'un reviewer (approve, approve w/ suggestions, wait for author, reject).
- **Résultat** : notification « <author> commented on / voted <vote> on <PR title> ». Clic → ouvre PR.

### UC8 — Notification commentaire sur mes WI
- **Déclencheur** : nouveau commentaire (auteur ≠ utilisateur) sur WI assigné.
- **Résultat** : notification « <author> commented on #ID title ». Clic → ouvre WI.

### UC9 — Rafraîchissement
- Polling automatique, intervalle réglable (défaut 2 min, min 1 min).
- Bouton « Refresh » manuel dans panneau.
- Heure dernière synchro visible.

### UC10 — Masquer des états
- **Acteur** : Utilisateur
- **Préconditions** : configuré, projets cochés.
- **Scénario nominal** :
  1. Settings → section « States ».
  2. App affiche liste unique des **noms** d'états (union tous types WI × projets suivis), triés, avec catégorie ADO.
  3. Utilisateur décoche états inutiles.
  4. Enregistrement → états masqués absents de tous menus statut (UC4).
  5. Seconde colonne « List » (ajout recette 2026-10-28) : état décoché → WI dans cet état absents de la section « Work Items » (UC3), du compteur de section et du badge icône. Notifications selon UC14.
  6. Boutons « Check All » / « Uncheck All » par colonne.
- **Variantes / erreurs** : nouvel état apparu côté ADO → visible par défaut. Masquage n'affecte **pas** l'affichage de l'état courant d'un WI dans la liste.
- **Postconditions** : préférence persistée.

### UC11 — Mettre en sourdine (mute)
- **Acteur** : Utilisateur
- **Préconditions** : configuré.
- **Scénario nominal** :
  1. Panneau → action « Mute notifications » → choix durée : 1 hour · Until tomorrow (9:00) · Until date… (sélecteur date, ex. retour de vacances) · Until I turn it back on.
  2. Aucune notification émise pendant sourdine.
  3. Polling et listes continuent de se mettre à jour normalement.
  4. Icône barre de menus indique état muted ; panneau affiche « Muted until <date> » + bouton « Unmute ».
  5. Fin d'échéance ou « Unmute » → notifications reprennent pour événements **postérieurs** uniquement.
- **Variantes / erreurs** : sourdine persistée → survit redémarrage app / Mac. Date passée choisie → refusée.
- **Postconditions** : événements survenus pendant sourdine jamais notifiés (pas de rafale au retour).

### UC12 — Masquer les tags de titre
- **Acteur** : Utilisateur
- **Contexte** : titres PR / WI souvent pollués par tags entre crochets, parfois 3-4 d'affilée (`[Backend][Hotfix][P1] Fix login`).
- **Préconditions** : configuré.
- **Scénario nominal** :
  1. Settings → onglet « Titles ».
  2. App liste les tags **détectés** (tout `[...]` n'importe où dans titres PR + WI des projets suivis), triés, avec nombre d'occurrences actuelles.
  3. Utilisateur coche tags à masquer, ou active « Hide all tags ».
  4. Enregistrement immédiat → tags masqués retirés des titres dans panneau **et** notifications.
- **Règles** :
  - Tag = texte entre `[` et `]`, sans crochet imbriqué, non vide. Position quelconque dans titre.
  - Comparaison insensible à la casse et aux espaces de bord (`[hotfix]` = `[ Hotfix ]`).
  - « Hide all tags » activé → tous tags retirés, y compris non encore détectés. Désactivé → seuls tags cochés retirés.
  - Nouveau tag détecté → visible par défaut (non coché).
  - Tags détectés mémorisés (persistés) même s'ils disparaissent des titres courants, pour garder les choix.
  - Après retrait : espaces multiples réduits à un, espaces / séparateurs de bord (` - `, `:`, `|`) supprimés.
  - Titre vide après retrait → titre original affiché.
  - Titre complet original toujours accessible (info-bulle de la ligne).
- **Postconditions** : préférence persistée.

### UC13 — Options d'affichage du panneau (ajout recette 2026-10-28)
- **Acteur** : Utilisateur
- **Scénario nominal** : Settings › General › section « Panel » :
  - « Panel width » : Standard (380 pt) · Wide (480 pt) · Extra Wide (600 pt). Défaut Standard.
  - « Wrap titles » : titres sur 2 lignes max au lieu d'une ligne tronquée. Défaut désactivé.
  - « Hide drafts in To Review » : PRs draft absentes de « To Review » et du badge. Défaut désactivé.
  - « Hide drafts in My PRs » : PRs draft absentes de « My PRs ». Défaut désactivé.
- **Règles** : filtres = affichage. Notifications des éléments masqués selon UC14. Section dont des éléments sont filtrés → mention « N hidden » sous la liste. Préférences persistées.

### UC14 — Notifier ou non les éléments masqués (ajout 2026-10-29)
- **Acteur** : Utilisateur
- **Scénario nominal** : Settings › General › Panel → interrupteur global « Notify for hidden items » (défaut **activé**, comportement antérieur conservé).
- **Élément masqué** = au moment de l'événement, selon le snapshot courant :
  - PR draft dans « To Review » avec « Hide drafts in To Review » ;
  - PR draft dans « My PRs » avec « Hide drafts in My PRs » ;
  - WI dont l'état est décoché dans Settings › States › List.
- **Désactivé** → aucun événement d'un élément masqué n'est notifié : review requested, commentaire / réponse / vote sur ma PR, WI assigné, commentaire WI.
- **Pas de rattrapage** : un élément qui redevient visible ne déclenche pas de notification pour ce qui s'est passé pendant qu'il était masqué ; ses événements suivants sont notifiés.
- Indépendant de la sourdine (UC11) : la sourdine coupe tout, cette option ne coupe que les éléments masqués.
- Le masquage des tags de titre (UC12) ne masque pas d'élément → hors règle.

### Fermeture du panneau (ajout recette 2026-10-28)
- Ouverture d'une fenêtre depuis le panneau (Settings…, Set Up…, « Update… » du bandeau PAT) → panneau fermé.
- Ouverture d'un lien depuis le panneau (clic ligne, « Open in Browser », « Show all … in browser… ») → panneau fermé.

### Ouverture des liens
- Clic ligne / notification → URL ouverte dans **navigateur par défaut**, nouvel onglet. Pas de détection d'onglet existant (navigateur cible : Firefox, non scriptable).

## Critères d'acceptation
- [ ] AC1 — Given app non configurée, When clic icône, Then panneau affiche « Not configured » + accès Settings.
- [ ] AC2 — Given PAT invalide, When enregistrement, Then message d'erreur, config non sauvée.
- [ ] AC3 — Given PAT valide, When enregistrement, Then PAT absent de tout fichier en clair (stockage sécurisé système) et liste projets proposée.
- [ ] AC4 — Given config valide, When clic icône, Then sections « To Review », « My PRs », « Work Items » affichées, filtrées sur projets cochés.
- [ ] AC5 — Given PR où utilisateur reviewer uniquement via groupe, Then PR **absente** de « To Review ».
- [ ] AC6 — Given clic ligne PR ou WI, Then URL web ADO correspondante ouverte dans navigateur par défaut.
- [ ] AC7 — Given WI état X, When ouverture menu statut, Then états proposés = états ADO du type de ce WI − masqués − X.
- [ ] AC7b — Given choix état Y dans menu, Then état ADO = Y et ligne reflète Y.
- [ ] AC8 — Given transition refusée par ADO, When choix état, Then message d'erreur affiché, état affiché inchangé.
- [ ] AC9 — Given premier cycle après lancement app, Then **aucune** notification (constitution baseline).
- [ ] AC10 — Given baseline établie, When nouveau WI assigné, Then une notification, une seule (pas de répétition cycles suivants).
- [ ] AC11 — Given baseline, When nouvelle PR avec utilisateur reviewer direct, Then une notification.
- [ ] AC12 — Given baseline, When autre personne crée thread ou répond dans thread sur ma PR, Then une notification.
- [ ] AC13 — Given baseline, When utilisateur lui-même commente sa PR, Then aucune notification.
- [ ] AC14 — Given baseline, When reviewer change vote sur ma PR, Then une notification avec vote.
- [ ] AC15 — Given baseline, When autre personne commente WI assigné, Then une notification.
- [ ] AC16 — Given clic notification, Then élément concerné ouvert dans navigateur.
- [ ] AC17 — Given réseau KO, When refresh, Then dernière donnée conservée + indicateur erreur, pas de crash, pas de notif parasite au retour réseau.
- [ ] AC18 — Given intervalle réglé à N min, Then refresh auto toutes N min.
- [ ] AC19 — Given app ouverte, Then pas d'icône Dock (app barre de menus uniquement).
- [ ] AC20 — Given ≥1 PR à relire ou WI nouveau non vu, Then icône barre de menus signale activité (badge / variante icône).
- [ ] AC21 — Given état « Blocked » masqué dans réglages, Then « Blocked » absent du menu statut de **tous** types WI qui le définissent.
- [ ] AC22 — Given WI dont état courant est masqué, Then état courant toujours affiché sur ligne.
- [ ] AC23 — Given WI d'un process Scrum (New/Approved/Committed/Done) et WI process Agile dans deux projets suivis, Then chacun propose ses propres états.
- [ ] AC24 — Given WI état catégorie Completed ou Removed, Then absent de section « Work Items ».
- [ ] AC25 — Given sourdine active, When nouvel événement notifiable, Then aucune notification, listes à jour.
- [ ] AC26 — Given sourdine « Until date D », When D atteinte, Then sourdine levée automatiquement, événements survenus pendant sourdine non notifiés, événements suivants notifiés.
- [ ] AC27 — Given sourdine active, When redémarrage app, Then sourdine toujours active jusqu'à échéance.
- [ ] AC28 — Given sourdine active, Then icône barre de menus distincte + mention « Muted until … » dans panneau.
- [ ] AC29 — Given configuration initiale, Then option « Launch at login » proposée cochée ; si validée, app relancée à l'ouverture de session suivante.
- [ ] AC30 — Given toute l'UI (panneau, Settings, notifications, erreurs), Then textes en anglais.
- [ ] AC31 — Given titres contenant `[Backend]` et `[Hotfix]`, When ouverture Settings › Titles, Then les deux tags listés avec nombre d'occurrences.
- [ ] AC32 — Given `[Hotfix]` coché, Then titre `[Backend][Hotfix] Fix [SSO] login` affiché `[Backend] Fix [SSO] login` dans panneau et notifications.
- [ ] AC33 — Given « Hide all tags » activé, Then `[Backend][Hotfix] Fix [SSO] login` affiché `Fix login`, y compris pour tag jamais vu.
- [ ] AC34 — Given `[hotfix]` coché, Then `[HOTFIX]` et `[ Hotfix ]` aussi retirés.
- [ ] AC35 — Given titre `[WIP]` seul et `[WIP]` masqué, Then titre original `[WIP]` affiché.
- [ ] AC36 — Given titre raccourci, When survol ligne, Then titre original complet en info-bulle.
- [ ] AC37 — Given nouveau tag apparu côté ADO, Then visible par défaut, ajouté non coché à la liste.
- [ ] AC38 — Given tag coché puis disparu des titres courants, Then choix conservé et réappliqué s'il revient.
- [ ] AC39 — Given panneau ouvert, When Settings…, Set Up… ou Update…, Then fenêtre ouverte au premier plan et panneau fermé.
- [ ] AC40 — Given panneau ouvert, When clic ligne, Open in Browser ou Show all…, Then URL ouverte et panneau fermé.
- [ ] AC41 — Given Settings › States, When Check All / Uncheck All d'une colonne, Then toutes les cases de cette colonne basculent, l'autre colonne inchangée.
- [ ] AC42 — Given « Resolved » décoché colonne List, Then WI en Resolved absents de Work Items, du compteur et du badge ; mention « 1 hidden ».
- [ ] AC43 — Given WI dans un état masqué de la liste et « Notify for hidden items » activé, When nouvelle assignation ou commentaire, Then notification émise.
- [ ] AC44 — Given WI masqué par son état, When passage à un état visible, Then WI réapparaît dans la liste.
- [ ] AC45 — Given « Hide drafts in To Review » et « Notify for hidden items » activé, Then PRs draft absentes de To Review et du badge ; notification « Review Requested » émise.
- [ ] AC46 — Given « Hide drafts in My PRs » et « Notify for hidden items » activé, Then mes PRs draft absentes de My PRs ; activité notifiée.
- [ ] AC47 — Given Panel width = Wide, Then panneau 480 pt, réglage persisté après redémarrage.
- [ ] AC48 — Given Wrap titles activé, Then titres longs sur 2 lignes max ; désactivé → 1 ligne tronquée.
- [ ] AC49 — Given réglages enregistrés avant UC14, When lancement, Then « Notify for hidden items » activé.
- [ ] AC50 — Given option désactivée et « Hide drafts in To Review », When review demandée sur une PR draft, Then aucune notification ; sur une PR non draft → notification.
- [ ] AC51 — Given option désactivée et « Hide drafts in My PRs », When commentaire ou vote sur ma PR draft, Then aucune notification.
- [ ] AC52 — Given option désactivée et « Resolved » décoché en List, When WI en Resolved assigné ou commenté, Then aucune notification.
- [ ] AC53 — Given option désactivée, When élément masqué redevient visible (PR publiée, état WI changé), Then aucune notification de rattrapage ; événement suivant notifié.
- [ ] AC54 — Given option désactivée et filtres « Hide drafts » désactivés, Then PRs draft notifiées normalement (seuls les éléments réellement masqués sont coupés).

## Cas limites
- PAT expire en cours d'usage → erreur auth visible, invite à mettre à jour PAT ; polling continue sans spam de notifs.
- Volume élevé (ex. 100+ PRs, 200+ WI) → listes scrollables, pas de blocage UI.
- Projet coché supprimé / plus accessible → ignoré, avertissement dans réglages.
- Même PR reviewer + créateur → affichée dans « My PRs » seulement.
- Process différents selon projets → états récupérés par projet × type WI (AC23).
- Même nom d'état dans catégories différentes selon type → masquage par nom s'applique à tous.
- État courant d'un WI renommé/supprimé côté process → affiché tel quel, menu statut fonctionne.
- Redémarrage app → nouvelle baseline, pas de rattrapage des événements manqués pendant arrêt.
- Fin de sourdine pendant que Mac en veille → levée au réveil, sans rafale.
- Mac en veille → refresh au réveil.
- Autorisation notifications refusée par utilisateur → app fonctionne, avertissement dans réglages.
- Crochets non fermés / imbriqués (`[WIP Fix`, `[[x]]`) → non traités comme tags, titre inchangé.
- Liens Markdown ou index dans titre (`array[0]`) → `[0]` détecté comme tag ; visible par défaut, masqué seulement si coché ou « Hide all tags ».
- Grand nombre de tags détectés (100+) → liste scrollable + champ de recherche.

- Tous les états décochés colonne List → section Work Items vide + « N hidden ».
- Colonne List n'affecte pas le menu statut (colonne Status Menu) et inversement.

## Hors périmètre (tags)
- Délimiteurs autres que crochets (`(...)`, `{...}`, préfixes `WIP:`).
- Masquage de tags par projet ou par type d'élément.
- Tags ADO natifs (champ `System.Tags` / labels PR) : non concernés, seuls les titres.

## Hors périmètre
- Plusieurs organisations / plusieurs PATs.
- PRs assignées via groupe / équipe.
- Voter, approuver, commenter, compléter une PR depuis l'app.
- Créer / éditer WI (hors statut) ; réassigner.
- Filtrage des états selon règles de transition (ADO valide, erreur remontée).
- Masquage d'états par type WI (masquage par nom uniquement).
- Réutilisation d'un onglet navigateur déjà ouvert.
- Rattrapage des événements survenus app fermée.
- OAuth / Entra ID ; Azure DevOps Server on-prem. Cible : cloud (`dev.azure.com/<org>` et `<org>.visualstudio.com`).
- Distribution App Store, auto-update.
- Builds / pipelines.

## Contraintes non fonctionnelles
- macOS natif, barre de menus uniquement, cible macOS récent (26+).
- PAT stocké dans stockage sécurisé système, jamais loggé.
- Scopes PAT minimaux documentés : Code (Read), Work Items (Read & Write), Project and Team (Read). Identity non requis (identité via `connectionData`). Pull Request Threads non requis (lecture des threads couverte par Code Read ; l'app n'écrit pas de commentaires).
- Respect quotas ADO : polling raisonnable, pas de requêtes par élément inutiles.
- Faible empreinte CPU/mémoire au repos.
- UI en anglais (libellés, notifications, réglages). Docs projet en français.
- Lancement au démarrage de session : proposé à la configuration initiale (UC1), modifiable dans Settings.

## Impact UI
**oui** — UI en anglais. Icône barre de menus (états : normal, activité, erreur, muted), panneau déroulant (3 sections + menu statut WI + bandeau muted + barre bas : synchro / refresh / mute / settings / quit), écran de configuration initiale (org, PAT, projets, launch at login), fenêtre Settings (org, PAT, projets, intervalle, launch at login, options panneau — largeur, retour à la ligne, drafts —, masquage états menu + liste, masquage tags de titre), notifications système.

## Questions ouvertes
- (aucune)
