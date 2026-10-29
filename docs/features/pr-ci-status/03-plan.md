# Statut CI des PRs — Plan

## Design retenu
Option B — une pastille par pipeline ([design/option-b.html](design/option-b.html)), contrat UI dans [02-design.md](02-design.md).

## Résumé de l'approche
Un appel ADO par PR (To Review + My PRs) à chaque sync : `policy/evaluations`. Le résultat est réduit en un modèle domaine `PRChecks` (pipelines build validation + « bloquantes toutes OK »), stocké dans le `Snapshot` par id de PR, comme `threads`. `EventDiffer` compare les `PRChecks` des PRs de *My PRs* connues pour produire `ciFailed` et `readyToMerge`. `NotificationGate` applique les 2 nouveaux toggles. `PanelState` expose les pastilles et le flag ready sur `PRRow` ; `PRRowView` affiche `CIDots` + `ReadyBadge`.

## API ADO
`GET {org}/{project}/_apis/policy/evaluations?artifactId=vstfs:///CodeReview/CodeReviewId/{projectId}/{prId}&api-version=7.1-preview.1`

Champs utilisés par évaluation :
- `status` : `queued` | `running` | `approved` | `rejected` | `notApplicable` | `broken`
- `configuration.id`, `isEnabled`, `isBlocking`, `type.id`, `settings.displayName`
- `context.buildId`, `context.isExpired`, `context.buildDefinitionName`

Build validation = `configuration.type.id == 0609b952-1397-4640-95ec-e00a01b2c241`.

## Décisions techniques
| Décision | Choix | Alternative écartée | Raison |
|---|---|---|---|
| Stockage | `Snapshot.checks: [Int: PRChecks]` (clé = id PR), `nil` = inconnu | Champ `checks` dans `PullRequest` | `PullRequest` reste = DTO PR ; même pattern que `threads` ; erreur API = absence de clé |
| Projet de l'`artifactId` | Ajouter `projectID` à `PullRequest` (déjà dans le DTO `repository.project.id`) | Lookup dans `prefs.projects` | Disponible gratuitement, aucun couplage aux prefs |
| Nom du pipeline | `settings.displayName` sinon `context.buildDefinitionName` sinon `"Build"` | Appel build definitions | Zéro appel en plus |
| Mapping statut | `approved`→passed, `rejected`/`broken`→failed, `running`→running, `queued` + `isExpired`→expired, `queued`→queued, `notApplicable` ou `isEnabled == false`→ignoré | — | Cas limites refinement |
| Ordre des pastilles | Ordre renvoyé par ADO | Tri par nom | Contrat UI |
| Prête à merger | Non draft **et** toute évaluation `isEnabled && isBlocking` est `approved` ou `notApplicable` **et** `mergeStatus` ≠ `conflicts`/`failure` ; policy *Require a merge strategy* ignorée (`rejected` jusqu'à la complétion — constaté en réel) | Policies seules | ADO grise *Complete* en cas de conflit ; `mergeStatus` déjà dans la réponse PR (ajout au DTO) — **à valider** |
| Détection échec | Pipeline `failed` dans new et (absent de old, non `failed` dans old, ou `buildId` différent) | Statut seul | Relance échouée deux fois entre deux syncs = nouvelle notif (UC2 variante) |
| Clé pipeline | `configuration.id` (policy) | Nom | Stable, unique par PR |
| Erreur API policies | `try?` par PR → pas de clé ; diff ignoré si old **ou** new inconnu | Échec du sync | AC16 : sync reste OK, pas de fausse notif |
| Appels | Séquentiels, comme `threads` | `TaskGroup` parallèle | Volume perso (~10–20 PRs) ; cohérence code ; optimisable plus tard |
| Filtrage notif | `NotificationGate` : toggles `notifyCIFailures` / `notifyReadyToMerge`, puis sourdine + masqués existants | Filtrer dans `EventDiffer` | Le differ reste pur (diff de données), règles de prefs centralisées |
| Prefs | 2 `Bool` défaut `true`, `decodeIfPresent` | — | Rétro-compat des réglages existants |

## Fichiers impactés
- `Sources/ADOCore/Models/Models.swift` — modifier : `PullRequest.projectID`, `PullRequest.mergeConflict` (Bool) ; créer `PipelineStatus`, `PipelineCheck`, `PRChecks` ; `Snapshot.checks`.
- `Sources/ADOCore/API/DTOs.swift` — modifier : `project.id`, `mergeStatus` ; créer `PolicyEvaluationDTO` + `model`.
- `Sources/ADOCore/API/ADOClient.swift` — créer : `prChecks(projectID:projectName:pullRequestID:)`.
- `Sources/ADOCore/Sync/SnapshotFetcher.swift` — modifier : fetch checks pour toReview + myPRs.
- `Sources/ADOCore/Sync/EventDiffer.swift` — modifier : cas `ciFailed`, `readyToMerge` + diff.
- `Sources/ADOCore/Domain/NotificationContent.swift` — modifier : 2 cas.
- `Sources/ADOCore/Domain/DisplayFilter.swift` — modifier : `hides(_ event:)` pour 2 cas (`hides(mine:)`).
- `Sources/ADOCore/Domain/Mute.swift` — modifier : `NotificationGate` applique les toggles.
- `Sources/ADOCore/Config/Preferences.swift` — modifier : `notifyCIFailures`, `notifyReadyToMerge`.
- `Sources/ADOCore/Presentation/PanelState.swift` — modifier : `PRRow.pipelines: [PipelineCheck]`, `PRRow.isReady` (My PRs uniquement) ; texte tooltip + label a11y (fonctions pures testables).
- `Sources/ADONotifier/Panel/Rows.swift` — modifier : `PRRowView` ; créer `CIDots`, `ReadyBadge`.
- `Sources/ADONotifier/Settings/SettingsView.swift` — modifier : 2 toggles.
- `Tests/ADOCoreTests/Fixtures/policy-evaluations.json` — créer.
- `Tests/ADOCoreTests/{ClientTests,SyncTests,DomainTests,PresentationTests,ConfigTests}.swift`, `Support.swift` — modifier.
- `README.md` — modifier si un scope PAT est nécessaire (cf. risques).

## Réutilisation
- `ADOClient.get` (version custom) — appel policy.
- Pattern `threads` du `SnapshotFetcher` — boucle par PR.
- `NotificationGate` / `DisplayFilter` — sourdine + éléments masqués.
- `NotificationContent.make` — format titre / sous-titre / corps, `threadID pr-<id>`.
- `VoteSummary` (structure `.help` + `accessibilityElement(children: .ignore)`), `DraftBadge` (style `READY`).
- `StubTransport`, `fixture()`, `snap()`, `pr()` — tests.

## Modèle (signatures)
```swift
public enum PipelineStatus: String, Codable, Sendable { case queued, running, expired, passed, failed }
public struct PipelineCheck: Codable, Hashable, Sendable, Identifiable {
    public var id: Int            // configuration.id
    public var name: String
    public var status: PipelineStatus
    public var isRequired: Bool
    public var buildID: Int?
}
public struct PRChecks: Codable, Hashable, Sendable {
    public var pipelines: [PipelineCheck]
    /// Toutes les policies bloquantes approuvées (build, reviewers, WI liés, commentaires…).
    public var blockingSatisfied: Bool
}
extension PullRequest { public func isReady(_ checks: PRChecks?) -> Bool }  // !isDraft && !mergeConflict && checks?.blockingSatisfied == true

case ciFailed(PullRequest, pipeline: String, isOptional: Bool)
case readyToMerge(PullRequest)
```

## Étapes
1. [x] Modèle + DTO : `projectID`, `mergeConflict`, `PipelineStatus/Check`, `PRChecks`, `PolicyEvaluationDTO.model`, `Snapshot.checks` (défaut `[:]`) — couvre cas limites (expiré, notApplicable, désactivé) — vérif : `swift build` + tests DTO.
2. [x] `ADOClient.prChecks` + fixture — vérif : `ClientTests` (URL, `artifactId`, api-version, mapping, réduction `blockingSatisfied`).
3. [x] `SnapshotFetcher` : checks pour toReview + myPRs, `try?` par PR — couvre AC16 — vérif : test fetcher (erreur 500 sur une PR → snapshot OK, pas de clé).
4. [x] `EventDiffer` : `ciFailed` / `readyToMerge` — couvre AC7–AC14, AC16 — vérif : `SyncTests`.
5. [x] Prefs + `NotificationGate` + `DisplayFilter` — couvre AC15, cas limites mute / masqués, AC6 (pas d'événement To Review) — vérif : `ConfigTests` (décodage ancien JSON), `DomainTests`.
6. [x] `NotificationContent` 2 cas — couvre AC7, AC10, AC11 (textes) — vérif : `DomainTests`.
7. [x] `PanelState` : `PRRow.pipelines`, `isReady`, `ciHelp`, `ciAccessibilityLabel` — couvre AC1–AC6, AC17 — vérif : `PresentationTests`.
8. [x] UI : `CIDots`, `ReadyBadge`, `PRRowView`, toggles Settings — couvre AC1–AC6, AC15, AC17 (visuel) — vérif : build + lint + contrôle manuel via `scripts/bundle.sh` (comparer à option-b.html).
9. [x] README (inchangé : PAT réel OK avec les scopes listés, cf. review #6) (scope PAT si besoin) — vérif : relecture.

## Stratégie de test
| AC | Type | Fichier test | Scénario |
|---|---|---|---|
| AC1 | unit | PresentationTests | 3 pipelines, 2 failed → `pipelines.count == 3`, label « CI: 2 of 3 failed » |
| AC2 | unit | PresentationTests | running/queued → statuts préservés ; tous passed → label « CI: succeeded » |
| AC3 | unit | PresentationTests | pas de clé / 0 pipeline → `pipelines` vide, help nil |
| AC4 | unit | PresentationTests | seul optionnel failed → `isRequired == false`, label « optional pipeline failed » |
| AC5 | unit | PresentationTests | texte tooltip exact (en-tête + lignes + `(optional)`) |
| AC6 | unit | PresentationTests + SyncTests | PR To Review a des pipelines ; diff ne produit aucun événement CI pour To Review |
| AC7 | unit | SyncTests + DomainTests | running→failed sur PR connue → 1 `ciFailed("Build")` ; contenu notif |
| AC8 | unit | SyncTests | 2 pipelines → 2 événements, même threadID |
| AC9 | unit | SyncTests | failed→failed même buildId → rien ; buildId différent → 1 événement |
| AC10 | unit | DomainTests | optionnel → sous-titre « … · optional » |
| AC11 | unit | SyncTests + DomainTests | non prête → prête → `readyToMerge` ; contenu notif |
| AC12 | unit | SyncTests | prête → prête → rien ; prête → non prête → prête → 2e événement |
| AC13 | unit | SyncTests | PR absente de old → aucun événement CI |
| AC14 | unit | SyncTests | draft avec blockingSatisfied → pas de ready ; conflit de merge → pas de ready |
| AC15 | unit | DomainTests | toggles off → événements CI filtrés, autres conservés |
| AC16 | unit | SyncTests + fetcher | checks nil d'un côté → aucun événement ; erreur HTTP sur policies → sync OK |
| AC17 | unit | PresentationTests | `isReady` vrai My PRs prête ; faux draft, non prête, To Review |
| Cas limites | unit | ClientTests | expiré → `.expired` ; notApplicable/désactivé/non-build ignorés dans `pipelines` mais comptés pour `blockingSatisfied` |
| Mute / masqués | unit | DomainTests | sourdine → rien ; draft masqué + notifyHidden off → rien |
| Prefs | unit | ConfigTests | JSON sans les clés → toggles `true` |
| Visuel | manuel | — | app bundlée vs maquette option B, clair/sombre, 380/480 |

## Commandes
- tests : `swift test` (ou `swift test --skip KeychainStoreTests`)
- lint : `xcrun swift-format lint --strict -r Sources Tests`
- build : `swift build` ; bundle manuel : `scripts/bundle.sh` puis `open "build/ADO Notifier.app"`

## Risques & mitigations
- **Scope PAT** : policy evaluations requiert a priori *Code (Read)* (déjà demandé). Si 401/403 en réel → l'erreur est absorbée par PR (pas d'icône), README mis à jour avec le scope manquant. Vérif manuelle étape 8.
- **API preview** (`7.1-preview.1`) : stable depuis des années ; version isolée dans un seul appel.
- **Charge** : +1 requête par PR par sync (≈ 20 req/2 min). Throttling ADO géré (`rateLimited`), mais une 429 sur policies est absorbée → pas de bannière. Acceptable.
- **Faux « ready »** : PR sans aucune policy bloquante → `blockingSatisfied == true` dès que non draft. Notif uniquement sur transition (draft → publié par ex.) ; comportement cohérent avec ADO (*Complete* actif).
- **Rétro-compat** : `Snapshot` en mémoire seulement ; `Preferences` décodage tolérant. Pas de migration.
- **Rollback** : changements additifs ; toggles off désactivent les notifs.
