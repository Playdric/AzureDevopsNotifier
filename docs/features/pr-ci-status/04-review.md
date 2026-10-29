# Statut CI des PRs — Review

## Verdict
✅ prêt — findings #1 à #4 corrigés (2026-10-29), #5 et #6 laissés en suggestion.

## Matrice AC → tests
| AC | Implémenté | Test | Statut |
|---|---|---|---|
| AC1 pastilles + 2 rouges | `CIDots`, `PRRow.pipelines` | `PRRowCITests.failuresCountedAndDetailed` | ✅ |
| AC2 en cours / succès | `PipelineDot`, `ciState` | `PRRowCITests.pendingAndPassed` | ✅ |
| AC3 aucune policy | `CIDots` vide | `PRRowCITests.nothingWithoutPipelines` | ✅ |
| AC4 optionnel atténué | opacité 0.45 | `PRRowCITests.optionalFailureIsDistinct` | ✅ (visuel manuel) |
| AC5 détail au survol | popover `CIDetail` | `ciHeader` + `status.label` testés ; survol vérifié en réel | ✅ |
| AC6 To Review : affichage, pas de notif | `prRow(mine: false)`, differ My PRs seul | `readyOnlyForMyPublishedPullRequests`, `reviewPullRequestsNeverProduceCIEvents` | ✅ |
| AC7 notif échec | `EventDiffer.checks`, `NotificationContent` | `failuresNotifiedPerPipeline`, `NotificationContentTests.contents` | ✅ |
| AC8 2 échecs → 2 notifs groupées | idem, `threadID pr-<id>` | `failuresNotifiedPerPipeline` | ✅ |
| AC9 échec persistant silencieux | comparaison `buildID` | `stillFailingSameBuildIsSilentButRerunFailureIsNot` | ✅ |
| AC10 « optional » | sous-titre | `NotificationContentTests.contents` | ✅ |
| AC11 notif ready | `isReady` transition | `readyOnTransitionOnly`, `contents` | ✅ |
| AC12 ready persistant silencieux | idem | `readyOnTransitionOnly` | ✅ |
| AC13 PR nouvelle absorbée | `oldMine[pr.id]` | `newPullRequestAbsorbsItsCIState` | ✅ |
| AC14 draft (+ conflit) jamais ready | `PullRequest.isReady` | `draftOrConflictIsNeverReady` | ✅ |
| AC15 toggles | `NotificationGate` | `ciTogglesDropOnlyTheirEvents`, `legacyJSONDecodesWithDefaults` | ✅ |
| AC16 erreur API | best effort fetcher, differ silencieux | `checksAreBestEffortPerPullRequest` (dernier état connu), `cancellationDuringChecksIsNotSwallowed`, `unknownChecksOnEitherSideAreSilent` | ✅ |
| AC17 badge READY | `ReadyBadge`, `PRRow.isReady` | `readyOnlyForMyPublishedPullRequests` ; vérifié en réel | ✅ |
| Cas limites (expiré, notApplicable, désactivé, merge strategy) | `PolicyEvaluationDTO` | `prChecksKeepBuildValidationOnly`, `blockingSatisfiedWhenEveryActiveBlockingPolicyApproved` | ✅ |

## Findings
| # | Sévérité | Fichier:ligne | Problème | Correction proposée |
|---|---|---|---|---|
| 1 | majeur | [SnapshotFetcher.swift:52](../../../Sources/ADOCore/Sync/SnapshotFetcher.swift#L52), [EventDiffer.swift:76](../../../Sources/ADOCore/Sync/EventDiffer.swift#L76) | Une erreur passagère (429, réseau) sur les policies d'une PR met `checks` à `nil` pour ce sync. Au sync suivant, `before == nil` → diff ignoré. Un pipeline passé en échec (ou une PR devenue prête) pendant ce trou n'est **jamais** notifié : au sync d'après, l'état est déjà « échoué / prêt » des deux côtés. | En cas d'erreur, reprendre `previous?.checks[pr.id]` (dernier état connu). Les pastilles restent celles du dernier sync réussi au lieu de disparaître ; le diff compare au dernier état connu. Mettre à jour AC16 (« affichée avec le dernier état connu »). Test : erreur puis échec → 1 notif. |
| 2 | mineur | [SnapshotFetcher.swift:58](../../../Sources/ADOCore/Sync/SnapshotFetcher.swift#L58) | `catch {}` avale aussi 401/429 sur les policies : un PAT sans scope suffisant donne « pas de pastilles », sans aucun signal. | Accepté pour un usage perso. Option : log `os_log` en debug. Pas de bannière (hors périmètre). |
| 3 | mineur | [SnapshotFetcher.swift:54](../../../Sources/ADOCore/Sync/SnapshotFetcher.swift#L54) | Re-throw de `CancellationError` non testé (mutation : supprimer le `catch is CancellationError` → aucun test rouge). | Test : transport qui lève `URLError(.cancelled)` sur `/policy/evaluations` → `fetch` lève `CancellationError`. |
| 4 | mineur | [PanelState.swift:60](../../../Sources/ADOCore/Presentation/PanelState.swift#L60) | En-tête `CI · optional pipeline failed` non testé (seul le label VoiceOver l'est). | Ajouter l'assertion dans `optionalFailureIsDistinct`. |
| 5 | suggestion | [SnapshotFetcher.swift:53](../../../Sources/ADOCore/Sync/SnapshotFetcher.swift#L53) | +1 requête séquentielle par PR et par sync. OK pour ~20 PRs ; plus lent au-delà. | Laisser ; paralléliser (`TaskGroup`) si le sync devient lent. |
| 6 | suggestion | README | Plan étape 9 : le scope PAT n'a pas été prouvé minimal (le PAT réel a peut-être plus que *Code (Read)*). | Laisser le README tel quel ; à revoir si un PAT minimal ne montre aucune pastille. |

## Corrections appliquées
- #1 : erreur policies → `previous?.checks[pr.id]` repris ; AC16 reformulé ; test fetcher sur 2 syncs.
- #2 : `Logger` (subsystem app, catégorie `sync`) en `.debug`, id PR public, erreur privée.
- #3 : `cancellationDuringChecksIsNotSwallowed`.
- #4 : assertion `ciHeader` optionnel.

## Écarts au plan / design (validés en cours de dev)
- Détail au survol : popover 300 ms au lieu de `.help()` natif (masqué par le tooltip de ligne, délai système trop long). `02-design.md` révisé.
- Tooltip titre : déplacé de la ligne entière vers le seul texte du titre ; délai app 300 ms (`NSInitialToolTipDelay`). Demandé en test réel.
- « Prête » : policy *Require a merge strategy* ignorée (`rejected` avant complétion, constaté sur PR réelle). Refinement + plan mis à jour.
- `mergeConflict` → `hasMergeConflict` (convention Bool).
- Hors périmètre respecté : pas de statuts externes, pas de notif To Review, pas d'icône barre de menus.

## Sécurité
- PAT : inchangé (Keychain, header Basic existant). Aucun log ajouté.
- `artifactId` construit depuis des valeurs ADO (id projet GUID, id PR entier), encodé par `URLQueryItem`. RAS.

## Résultats commandes
- tests : `swift test` → 98 tests, 17 suites, verts (`--skip KeychainStoreTests` : 97 verts).
- lint : `xcrun swift-format lint --strict -r Sources Tests` → 0 erreur.
- build : `swift build` OK ; `scripts/bundle.sh` OK ; vérification manuelle en réel (pastilles, popover, READY, tooltip titre).
