# Statut CI des PRs — Design

## Référence existante
- Design system / lib : SwiftUI natif macOS 26, `MenuBarExtra(.window)`, `Form(.grouped)` pour Settings. Pas de lib tierce.
- Tokens (source) : couleurs sémantiques système (`.red`, `.green`, `.orange`, `.secondary`, `.accentColor`), `.caption` pour la ligne méta. Maquettes : tokens copiés de `docs/features/ado-menubar-notifier/design/shared.html`.
- Écrans de référence : panel option B (`ado-menubar-notifier/design/option-b.html`), `PRRowView` ([Rows.swift](../../../Sources/ADONotifier/Panel/Rows.swift)), `GeneralSettingsView` section Notifications ([SettingsView.swift](../../../Sources/ADONotifier/Settings/SettingsView.swift)).
- Composants réutilisables : `VoteSummary` (symbole + compteur, `.help`, label a11y), `DraftBadge`, `CategoryDot`, `Toggle` à deux `Text` (titre + aide), `.help()` natif.

## Contraintes héritées
- Ligne PR : 2 lignes (titre / méta `.caption` secondaire). Votes alignés à droite en My PRs ; ligne méta To Review sans élément à droite aujourd'hui.
- Détail au survol = `.help()` natif → **texte brut multi-lignes** uniquement (pas de couleurs ni mise en forme). Clic sur la ligne = ouvre la PR (inchangé).
- Orange réservé : *Waiting for author*, *Resolved*.
- Notifications : titre = événement, sous-titre = détail, corps = titre PR nettoyé, `threadID pr-<id>`.
- Ton : anglais, Title Case titres/boutons, sentence case aides.

## Options
### Option A — Glyph + counter
- Maquette : design/option-a.html
- Principe : un SF Symbol agrégé à droite de la ligne méta, avant les votes. `xmark.circle.fill` rouge + compteur si > 1 (échec requis) ; `xmark.circle` rouge atténué (optionnel seul) ; `clock` gris (en file / en cours / expiré) ; `checkmark.circle` vert (tout OK) ; `arrow.triangle.merge` vert (My PRs prête à merger).
- Avantages : 12–20 px, même grammaire que `VoteSummary`, ne tronque pas la méta.
- Inconvénients : détail par pipeline seulement au survol.
- Écarts à l'existant : aucun (nouveau composant `CIStatusBadge` calqué sur `VoteSummary`).

### Option B — One dot per pipeline (retenue)
- Maquette : design/option-b.html
- Principe : une pastille 7 px par pipeline (rouge / vert / anneau orange en cours / anneau gris), optionnel = opacité réduite, « +n » au-delà de 6. Ready = badge `READY` façon `DRAFT`.
- Avantages : nombre d'échecs vs total visible sans survol.
- Inconvénients : info portée par la couleur seule (rouge/vert), largeur variable, réutilise l'orange.
- Écarts : orange pour « en cours » ; nouveau badge `READY`.

### Option C — Text capsule
- Maquette : design/option-c.html
- Principe : capsule teintée « ✕ 2 Failed », « ◷ Running », « ✓ Passed », « ✕ Optional ». Ready = badge `READY`.
- Avantages : explicite.
- Inconvénients : 55–70 px, tronque repo/auteur en 380 px ; concurrence avec les votes.
- Écarts : capsule teintée colorée (pill WI neutre) ; nouveau badge `READY`.

## Commun aux 3 options
- Tooltip `.help()` : `CI · 2 of 4 failed` puis une ligne par pipeline `✕ PR-Build — Failed`, `(optional)` suffixé, `Ready to merge` en fin si applicable.
- VoiceOver : `CI: 2 failed` / `CI: optional pipeline failed` / `CI: running` / `CI: succeeded` (+ `, ready to merge`).
- Compteur = nombre total de pipelines échoués (requis + optionnels).
- Aucune policy → rien affiché. Erreur API policies → rien affiché.
- Notifications : `CI Failed` / sous-titre `<pipeline>` ou `<pipeline> · optional` / corps titre PR. `Ready to Merge` / sous-titre repo / corps titre PR.
- Settings › General › Notifications : 2 toggles insérés entre statut d'autorisation et Mute — `CI failures` (« When a pipeline fails on one of your pull requests. »), `Ready to merge` (« When one of your pull requests can be completed. »).

## Contrôle de cohérence
| Point | A | B | C |
|---|---|---|---|
| Composants réutilisés | modèle `VoteSummary`, `.help`, `Toggle` | `CategoryDot`, `DraftBadge`, `Toggle` | `DraftBadge`, `Toggle` |
| Nouveaux composants | `CIStatusBadge` | `CIDots`, `ReadyBadge` | `CICapsule`, `ReadyBadge` |
| Tokens hors système | aucun | aucun | aucun |
| Patterns d'interaction | identiques (survol = help) | identiques | identiques |
| Vocabulaire | aligné ADO (Failed, Succeeded) | idem | idem |
| États vide / erreur | rien affiché | idem | idem |
| Accessibilité | symbole forme + couleur, label | couleur seule visuellement | texte |

## Recommandation
**Option A** : la plus compacte, zéro écart à l'existant, distingue échec requis / optionnel / en cours par la forme (pas seulement la couleur). Le « combien de pipelines KO » reste visible via le compteur ; le détail via tooltip.

## Décision
- Révision 2026-10-29 : tooltip natif → popover au survol (voir Contrat UI). Tooltip des titres : délai app ramené à 300 ms (`NSInitialToolTipDelay`).
**Option B retenue** (2026-10-29), ajustements :
- « En cours » (running) = anneau **bleu accent** (comme ADO / In Progress WI), pas orange. Maquette mise à jour.
- Info couleur seule acceptée : pleine (terminé) vs anneau (non terminé) + tooltip + VoiceOver `CI: 2 of 4 failed`.
- Marqueur **Ready** affiché dans My PRs : badge `READY` vert avant le titre (après `DRAFT` ; jamais les deux, draft ≠ ready). Ajouté au refinement (UC5, AC17).

## Contrat UI pour le dev
- Composants à réutiliser : `PRRowView` (ligne méta : zone droite), `VoteSummary` (reste à droite, après les pastilles), style `DraftBadge` (copié pour `READY`), `Toggle` titre + aide, `.help()`.
- Composants à créer :
  - `CIDots` : HStack spacing 3 de cercles 7 pt, ordre = ordre ADO des évaluations, max 6 puis `+n` (`.caption2`/10 pt, secondaire). Failed = `.red` plein ; Succeeded = `.green` plein ; Running = anneau 1.5 pt `.accentColor` ; Queued / Expired = anneau 1.5 pt `.tertiary` ; optionnel = opacité 0.45. `.help(<texte tooltip>)`, `accessibilityElement(children: .ignore)` + label.
  - `ReadyBadge` : texte `READY` 9 pt semibold, padding 5/1, rayon 4, fond `.green.opacity(0.18)`, texte `.green`.
- Placement : ligne méta, à droite (`Spacer`), ordre `CIDots` puis `VoteSummary`, espacement 8. To Review : `CIDots` seul à droite.
- Détail au survol (révisé 2026-10-29, test réel) : **popover** `CIDetail` après 300 ms de survol des pastilles, fermée à la sortie. `.help()` écarté : un `.help` dans le label du bouton de ligne est masqué par celui de la ligne, et délai système ~1 s. Contenu : en-tête gras `CI · 2 of 4 failed` | `CI · optional pipeline failed` | `CI · 2 of 4 pending` | `CI · all 3 succeeded` ; grille pastille + nom (+ `optional` secondaire) + statut secondaire (`Failed`, `Succeeded`, `Running`, `Queued`, `Expired — re-queue needed`) ; si ready : `Ready to merge` vert avec `checkmark.circle.fill`.
- VoiceOver : `CI: N of M failed` / `CI: optional pipeline failed` / `CI: running` / `CI: succeeded` (+ `, ready to merge`).
- États à implémenter : aucune policy (rien), erreur API (rien), en file, en cours, expiré, succès, échec requis, échec optionnel seul, > 6 pipelines, ready.
- Notifications : `CI Failed` · sous-titre `<pipeline>` ou `<pipeline> · optional` · corps titre PR nettoyé ; `Ready to Merge` · sous-titre repo · corps titre PR. `threadID pr-<id>`.
- Settings › General › Notifications : 2 `Toggle` entre statut autorisation et Mute — `CI failures` / « When a pipeline fails on one of your pull requests. » ; `Ready to merge` / « When one of your pull requests can be completed. ». Défaut : activés.
- Règles : couleurs système uniquement ; orange non utilisé ; Title Case titres de notif ; aucun changement au clic ligne.
