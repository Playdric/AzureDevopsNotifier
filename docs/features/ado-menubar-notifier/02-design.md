# ADO Menu Bar Notifier — Design

## Référence existante
- **Projet greenfield** : aucun code UI existant. Seule référence = plateforme.
- Design system / lib : SwiftUI natif macOS 26 (Liquid Glass), Apple HIG. Aucune lib tierce.
- Tokens (source) : couleurs sémantiques système (`.primary`, `.secondary`, `.tertiary`, `Color.accentColor`, `.red/.orange/.green`), police système SF Pro (13 pt corps, 11 pt secondaire), matériaux système. Valeurs hex des maquettes = approximations pour le navigateur, **jamais** codées en dur dans l'app.
- Exception tokens : couleurs des types WI (Bug `#CC293D`, User Story / PBI `#009CCC`, Task `#F2CB1D`…) → idéalement lues depuis l'API ADO (`workitemtypes[].color`), fallback gris.
- Écrans de référence : menus barre de menus système (Wi‑Fi, Contrôle), popovers type Calendrier / Rappels.
- Composants réutilisables : `MenuBarExtra`, `Menu`, `Picker(.segmented)`, `Form(.grouped)`, `Toggle`, `Settings` scene + `TabView`, `UNUserNotificationCenter`, `SMAppService` (launch at login).
- Incohérence existante : aucune (pas d'existant).

## Écrans communs (toutes options) — `design/shared.html`
- **Icône barre de menus** (template image monochrome) : normal · activité (glyphe + compteur) · erreur (glyphe + `!`) · muted (glyphe + cloche barrée) · non configuré (glyphe estompé). Priorité : non configuré > muted > erreur > activité > normal.
- **Configuration initiale** : fenêtre 2 étapes — `Connect` (org URL, PAT + scopes requis + lien « Create a token… ») → `Projects` (cases à cocher, « Launch at login » coché). Validation PAT avec spinner ; erreurs inline.
- **Settings** : scene `Settings` native, onglets toolbar `General` (intervalle 1/2/5/10/15/30 min, launch at login, statut permission notifications + « Open System Settings… »), `Account` (org, PAT Keychain, « Signed in as », bouton Save avec validation), `Projects` (cases, projet inaccessible signalé), `Titles` (UC12 : switch « Hide all tags », recherche, liste des tags détectés `[Tag]` + nb de titres ou « Not seen recently », case = masqué, liste grisée si Hide all ; aperçu avant/après), `States` (union des noms d'états, catégorie ADO, case = visible).
- **Notifications** : titre = événement, corps = élément (+ repo/auteur ou extrait commentaire). Regroupées par élément (`threadIdentifier`). Clic → navigateur.

## Options (panneau)

### Option A — Native menu (NSMenu)
- Maquette : design/option-a.html
- Principe : `MenuBarExtra(.menu)`, menu système pur ; items avec sous‑titre ; sous‑menu par WI (« Open in Browser » + « Move to » états) ; sous‑menu « Mute Notifications ».
- Avantages : 100 % natif, clavier/VoiceOver gratuits, dev le plus rapide, zéro layout custom.
- Inconvénients : item à sous‑menu non cliquable → ouvrir un WI = 2 niveaux ; pas de contenu riche (votes en texte, pas de spinner, pas de bandeau) ; erreur de transition ADO → alerte modale (menu fermé) ; pas de scroll propre → plafond 10 lignes/section ; « Until Date… » nécessite une fenêtre séparée ; menu fermé après chaque action.
- Écarts à l'existant : aucun.

### Option B — Popover, sections empilées (recommandée)
- Maquette : design/option-b.html
- Principe : `MenuBarExtra(.window)`, panneau verre 380 pt, max ~600 pt, 3 sections repliables (`To Review`, `My PRs`, `Work Items`) avec compteurs ; ligne 2 niveaux ; pill d'état sur WI → `Menu` natif « Move to » ; bandeaux haut (réseau, PAT, muted) ; barre bas : synchro · Refresh · Mute (menu) · More (Settings…, Quit).
- Avantages : tout visible d'un coup d'œil ; changement d'état en 1 clic + choix ; erreur ADO inline sous la ligne, état inchangé ; spinner pendant mise à jour ; scroll natif ; sélecteur de date intégré au menu Mute.
- Inconvénients : layout custom SwiftUI (plus de code qu'A) ; panneau haut si 3 listes longues (atténué par repli + scroll).
- Écarts à l'existant : aucun (popover = pattern standard des apps barre de menus macOS).

### Option C — Popover à onglets
- Maquette : design/option-c.html
- Principe : identique à B, mais `Picker(.segmented)` en tête : une liste à la fois, compteur par onglet (bleu si nouveautés). Onglet initial = premier avec nouveautés, sinon dernier utilisé.
- Avantages : plus de hauteur par liste ; panneau compact.
- Inconvénients : un clic de plus pour voir les autres listes ; nouveautés hors onglet courant moins visibles.
- Écarts à l'existant : aucun.

## Décisions de détail communes (B et C)
- Point bleu = élément nouveau depuis dernière ouverture du panneau ; alimente compteur icône (AC20) ; effacé à la fermeture du panneau.
- Draft : badge `DRAFT` avant le titre.
- Votes « My PRs » : icônes colorées (✓ vert approved, ✓~ approved w/ suggestions, ⏸ orange waiting, ✕ rouge rejected, ○ no vote) + compte ; libellé accessible complet.
- Pill d'état : point couleur catégorie (Proposed gris, In Progress bleu, Resolved orange, Completed vert) + nom.
- Passage en Completed/Removed : état mis à jour, ligne retirée au prochain refresh (AC24).
- Plus de 50 lignes par section : lien « Show all N … in browser… ».
- Vides : texte une ligne par section (« No pull requests waiting for your review. », « You have no active pull requests. », « No open work items assigned to you. »).
- Premier chargement : skeleton ; refresh suivants : spinner dans barre bas seulement, données conservées.

## Ton éditorial
- Anglais (AC30). **Title Case** pour boutons, menus, titres de section (HIG) → `To Review`, `My PRs`, `Work Items` (le refinement écrivait « To review », « Work items » : écart de casse à valider). Phrases (messages, aides) en sentence case.
- Termes ADO conservés : *pull request*, *work item*, *personal access token*, noms d'états tels qu'ADO.

## Contrôle de cohérence
| Point | A | B | C |
|---|---|---|---|
| Composants système réutilisés | Menu, Settings, Form | MenuBarExtra(.window), Menu, Settings, Form | + Picker(.segmented) |
| Nouveaux composants | aucun | Row PR, Row WI, StatePill, Banner, SectionHeader, Footer | idem B sans SectionHeader |
| Tokens hors système | couleurs type WI | idem | idem |
| Patterns d'interaction | menu natif | popover natif + menus natifs | idem B |
| États vide / chargement / erreur | dégradés (items désactivés, alerte) | complets | complets |
| Accessibilité | native | labels explicites, focus visible, flèches dans menus | idem |

## Recommandation
**Option B** : seule à couvrir tous les états du refinement sans détour (erreur transition inline AC8, bandeaux réseau/PAT/muted AC17/AC28, sélecteur de date de sourdine) tout en gardant les 3 listes visibles d'un coup d'œil — but premier de l'app. Coût dev modéré, composants SwiftUI standards.

## Décision
**Option B retenue** (2026-10-28), sans ajustement. Écrans communs (`shared.html`) validés tels quels. Ajout 2026-10-28 : onglet Settings `Titles` (masquage tags de titre, UC12) dans écrans communs. Casse : **Title Case** (HIG) pour titres, boutons, menus ; 01-refinement.md aligné.

## Contrat UI pour le dev
- **Composants système à réutiliser** : `MenuBarExtra(.window)`, `Menu` (popup natif pour états, Mute, More), `Settings` scene + `TabView` (General / Account / Projects / Titles / States), `Form(.grouped)`, `Toggle(.switch)`, `Picker`, `DatePicker`, `ProgressView`, `UNUserNotificationCenter`, `SMAppService.mainApp`, `NSWorkspace.open` (navigateur par défaut). Matériaux et couleurs sémantiques système uniquement.
- **Composants à créer** :
  - `MenuBarLabel` : glyphe template + variantes (normal, compteur, `!`, cloche barrée, estompé), priorité non configuré > muted > erreur > activité > normal.
  - `PanelView` : bandeau(x) · liste scrollable · `PanelFooter` ; largeur 380 pt, hauteur max ~600 pt.
  - `SectionHeader` : chevron repli + titre + compteur ; état replié persisté par section.
  - `PRRow` (variantes To Review / My PRs), `WIRow`, `StatePill`, `VoteSummary`, `DraftBadge`, `NewDot`.
  - `StatusBanner` : variantes network error, token expired (bouton « Update… » → Settings › Account), muted (bouton « Unmute »).
  - `InlineRowError` : erreur ADO sous la ligne WI, refermable.
  - `MuteMenu` : For 1 Hour · Until Tomorrow, 9:00 · Until Date… (date+heure, futur uniquement, « Choose a date in the future. ») · Until I Turn It Back On.
  - `TitleCleaner` (logique pure, testée) : retire tags `[...]` masqués partout dans le titre, normalise espaces / séparateurs de bord, fallback titre original si vide. Utilisé par lignes panneau **et** notifications.
  - `TitlesSettingsView` : switch Hide all, recherche, liste tags détectés (persistés), aperçu.
  - `SetupWindow` : 2 étapes Connect → Projects, Launch at login coché par défaut.
- **États à implémenter** : non configuré · premier chargement (skeleton) · nominal · vide par section · gros volume (scroll, > 50 → « Show all N … in browser… ») · refresh en cours (spinner footer, données conservées) · erreur réseau (bandeau + dernière synchro) · PAT expiré · muted · changement d'état en cours (spinner dans pill) · transition refusée (erreur inline, état inchangé) · aucun état disponible (« No state available ») · permission notifications refusée (Settings › General).
- **Libellés figés** : sections `To Review`, `My PRs`, `Work Items` ; vides « No pull requests waiting for your review. » / « You have no active pull requests. » / « No open work items assigned to you. » ; menu état en-tête « Move to » ; More : « Settings… ⌘, », « Quit ADO Notifier ⌘Q » ; Refresh ⌘R ; notifications : titre = événement (« Review Requested », « Work Item Assigned », « <author> commented », « <author> voted <vote> », « <author> commented on #ID »), corps = élément.
- **Stockage PAT (décision 2026-10-28)** : saisi via `SecureField` (setup + Settings › Account), écrit **par l'app** dans le Keychain (`SecItemAdd/Update`) → ACL liée à la signature de l'app. `kSecClassGenericPassword`, service `com.<you>.ado-notifier`, account = URL org, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, `kSecAttrSynchronizable=false`. Jamais réaffiché, jamais loggé ; champ vide = token conservé. Pas de création via CLI `security` (ACL de confiance à `/usr/bin/security` → tout script utilisateur lit le PAT sans invite).
- **Règles de cohérence** :
  - Aucune couleur/police codée en dur sauf couleurs de type WI (API ADO, fallback gris).
  - Point bleu = nouveau depuis dernière ouverture du panneau ; effacé à la fermeture.
  - Clic ligne = ouvrir navigateur ; clic pill = menu états ; jamais d'autre action sur la ligne.
  - Couleur catégorie d'état : Proposed gris, In Progress accent, Resolved orange, Completed vert, Removed tertiaire.
  - Votes : icône + couleur + libellé accessible complet (jamais la couleur seule).
  - Titre affiché = titre nettoyé ; info-bulle (`.help`) = titre original complet.
  - Title Case pour titres / boutons / menus, sentence case pour messages et aides.
  - Navigation clavier complète, labels VoiceOver sur boutons-icônes, Dark/Light automatiques.

## Ajustements recette (2026-10-28)
Maquette : `design/shared.html` (onglets General et States).
- **General › Panel** : `Picker` « Panel width » (Standard 380 / Wide 480 / Extra Wide 600 pt), `Toggle` « Wrap titles » (2 lignes max), `Toggle` « Hide drafts in To Review », `Toggle` « Hide drafts in My PRs ». Note : « Hidden items still send notifications. »
- **States** : 2 colonnes de cases « Menu » (états du menu statut, existant) et « List » (états affichés dans Work Items). En-tête de colonne avec boutons « All » / « None » (Check All / Uncheck All).
- **Panneau** : largeur selon réglage ; titres `lineLimit(wrap ? 2 : 1)` ; section avec éléments filtrés → ligne secondaire « N hidden » sous la liste (caption, couleur secondaire).
- **Notify for hidden items** (UC14, 2026-10-29) : `Toggle` dans General › Panel, sous les filtres drafts, sous-titre « Drafts and work items hidden by your filters. ». Remplace la note de pied « Hidden items still send notifications. ». En-tête States : « List: work items in this state shown in the panel. » (mention « still notified » retirée). Info-bulle « N hidden » : « Hidden by your display settings. » + « Notifications are still sent. » seulement si l'option est active.
- **Fermeture** : le panneau se ferme à l'ouverture d'une fenêtre (Settings…, Set Up…, Update…) et d'un lien (ligne, Open in Browser, Show all…).
- **Titres de section** (retours 2026-10-28) : capsule façon verre dessinée (`GlassCapsule` : `.ultraThinMaterial` + voile blanc 10 % sombre / 38 % clair + bordure dégradée + ombre) — `.glassEffect` testé puis écarté : invisible sur le panneau déjà en verre, libellé couleur primaire, épinglée en haut pendant le défilement de sa section (`LazyVStack(pinnedViews: .sectionHeaders)`). Choisie sur maquette comparative `design/section-headers.html` (option B) ; bandeau gris opaque abandonné (rendu non natif).
