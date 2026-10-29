# ADO Menu Bar Notifier — Review

## Verdict
✅ prêt — findings #1 à #7 corrigés, #8 sans objet (vérifié). Recette réelle faite par l'utilisateur (lots 1 et 2).

_Verdict initial : ⚠️ prêt avec réserves (1 majeur, 5 mineurs)._

## Matrice AC → tests
| AC | Implémenté | Test | Statut |
|---|---|---|---|
| AC1 | PanelState / NotConfiguredView | PanelStateTests.notConfigured | ✅ |
| AC2 | ADOClient 401/203 → unauthorized ; setup n'enregistre rien | ADOClientTests.rejectedTokenIsUnauthorized | ✅ |
| AC3 | KeychainStore, Preferences sans secret | KeychainStoreTests, PreferencesTests.encodedPreferencesHaveNoPATField | ✅ |
| AC4 | SnapshotFetcher projets suivis | SnapshotFetcherTests.buildsFilteredSnapshot | ✅ |
| AC5 | filtre reviewer direct `!isContainer` | idem (PR 102) | ✅ |
| AC6 | WebLinks + PanelNavigation.openURL | WebLinksTests + recette | ✅ |
| AC7 | StateMenu.options | StateMenuTests.optionsExcludeCurrentAndHidden | ✅ |
| AC7b | updateState + maj snapshot | ADOClientTests.updateStateSendsJSONPatch + recette | ✅ |
| AC8 | ADOError.server(message) + InlineRowError | ADOClientTests.transitionRefusalCarriesADOMessage + recette | ✅ |
| AC9 | baseline SyncService | SyncServiceTests.baselineThenDiff… | ✅ |
| AC10–AC15 | EventDiffer | EventDifferTests (6 tests) | ✅ |
| AC16 | userInfo url + délégué | NotificationContentTests + recette | ✅ |
| AC17 | lastGood conservé ; synchro annulée ignorée | SyncServiceTests (+ cancelledCycleReturnsNil), ADOClientTests.cancelledRequest…, PanelStateTests.errorBannersKeepData | ✅ |
| AC18 | intervalle + clamp | SyncServiceTests.runSleeps…, PreferencesTests | ✅ |
| AC19 | LSUIElement | smoke test (`UIElement`) | ✅ |
| AC20 | icône activité | PanelStateTests.activityCounts… | ✅ |
| AC21–AC24 | StateMenu / filtre catégorie | StateMenuTests, SnapshotFetcherTests | ✅ |
| AC25–AC27 | Mute, NotificationGate, persistance | MuteTests, PreferencesTests | ✅ |
| AC28 | icône + bandeau muted | PanelStateTests.mutedIconAndBanner | ✅ |
| AC29 | SMAppService | recette | ✅ (voir #7) |
| AC30 | chaînes anglaises | NotificationContentTests + relecture | ✅ |
| AC31–AC38 | TitleCleaner / TagCatalog | TitleCleanerTests, TagCatalogTests | ✅ |
| AC39–AC40 | PanelNavigation (dismiss) | recette | ✅ |
| AC41 | All / None par colonne | recette | ✅ |
| AC42–AC46 | filtres d'affichage PanelState | PanelStateTests (3 tests) | ✅ |
| AC47 | PanelWidth + décodage tolérant | PreferencesTests (2 tests) | ✅ |
| AC48 | lineLimit wrap | recette | ✅ |

Hors périmètre respecté (pas de vote / commentaire / multi-org / OAuth). PAT jamais loggé, HTTPS uniquement, hôtes ADO cloud seulement.

## Findings
| # | Sévérité | Fichier:ligne | Problème | Correction proposée |
|---|---|---|---|---|
| 1 | majeur | Sources/ADONotifier/AppModel.swift:55-75, Sources/ADOCore/Sync/SyncService.swift (cycle) | `startPolling()` annule l'ancienne tâche, mais un cycle déjà en vol (polling ou Refresh manuel) termine quand même et appelle `handle` : (a) l'annulation de la requête devient `.failed(.network)` → bandeau « Can't reach Azure DevOps » et icône erreur juste après un changement de projets / compte ; (b) un snapshot de l'ancien périmètre peut écraser le nouvel état ou émettre des notifications. Non couvert par les tests. | `SyncService.cycle()` renvoie `nil` si la tâche est annulée (`CancellationError`, `URLError.cancelled`) ; `AppModel` ignore les résultats d'un `SyncService` qui n'est plus le courant (comparaison d'identité). Test : cycle annulé → `nil`. |
| 2 | mineur | Sources/ADOCore/API/ADOClient.swift:81 | `workitemsbatch` sans `errorPolicy` : un WI supprimé / déplacé entre la WIQL et le batch fait échouer tout le cycle (bandeau erreur jusqu'au cycle suivant). | `"errorPolicy": "omit"` + décodage `[WorkItemDTO?]` en ignorant les `null`. Test fixture avec `null`. |
| 3 | mineur | Sources/ADOCore/Presentation/PanelState.swift (bannières) | 429 affiché « Can't reach Azure DevOps » ; `Retry-After` non respecté (écart au plan). | Libellé dédié « Azure DevOps is throttling requests » ; Retry-After hors scope perso, accepter l'écart. |
| 4 | mineur | Tests/ADOCoreTests/SyncTests.swift:156 | `concurrentCycleIsSkipped` dépend d'un `sleep(50 ms)` → potentiellement instable sous charge. | Attendre un signal « fetch démarré » au lieu d'un délai. |
| 5 | mineur | Sources/ADONotifier/Settings/SettingsView.swift (ProjectsSettingsView.onChange) | Chaque case cochée relance le polling (nouvelle baseline, skeleton, rafale de requêtes). | Appliquer après 1 s sans changement (debounce). |
| 6 | mineur | Tests/ADOCoreTests/ConfigTests.swift (KeychainStoreTests) | Test dépendant du trousseau de session déverrouillé (échouerait en CI / session verrouillée). | Accepté (projet perso) ; tag `.keychain` pour pouvoir l'exclure. |
| 7 | suggestion | Sources/ADONotifier/System/System.swift (LaunchAtLogin) | Erreurs `SMAppService` ignorées ; statut `requiresApproval` invisible. | Afficher le statut dans Settings › General si ≠ enabled. |
| 8 | suggestion | Sources/ADONotifier/Panel/Rows.swift | Environnements `model` / `navigation` injectés dans des vues qui ne s'en servent pas. | Nettoyage (`/simplify`). |

## Corrections appliquées
| # | Statut | Correction | Test |
|---|---|---|---|
| 1 | corrigé | `ADOClient` : requête annulée → `CancellationError` ; `SyncService.cycle()` → `nil` si annulé ; `AppModel.handle(_:from:)` ignore une synchro qui n'est plus la courante | `cancelledCycleReturnsNil`, `cancelledRequestIsCancellationNotNetwork` |
| 2 | corrigé | `workitemsbatch` avec `errorPolicy: omit`, entrées `null` ignorées | `batchOmitsMissingWorkItems` |
| 3 | corrigé | bandeau dédié `throttled` (« Azure DevOps is throttling requests ») ; Retry-After non géré (écart accepté : le cycle suivant réessaie) | `errorBannersKeepData` |
| 4 | corrigé | test synchronisé sur un signal « fetch démarré », plus de délai | `concurrentCycleIsSkipped` |
| 5 | corrigé | Settings › Projects appliqué 1 s après le dernier clic, ou à la fermeture | recette |
| 6 | corrigé | suite `KeychainStoreTests` taguée `.keychain` ; `swift test --skip KeychainStoreTests` documenté dans le README | — |
| 7 | corrigé | Settings › General : avertissement si Launch at login est activé mais inopérant + bouton « Open Login Items… » | recette |
| 8 | sans objet | revérifié : chaque environnement injecté dans `Rows.swift` est utilisé | — |

## Résultats commandes
- tests : `swift test` → 75 tests / 14 suites, tous verts (`--skip KeychainStoreTests` → 74 verts).
- lint : `xcrun swift-format lint --strict -r Sources Tests` → 0 finding.
- build : `swift build` OK ; `scripts/bundle.sh` OK (signature ad-hoc) ; app lancée en `UIElement`.

## Après review
- Titres de section : capsule façon verre épinglée (`GlassCapsule`), choisie sur maquette `design/section-headers.html`, validée en réel par l'utilisateur. Tests 75/75, lint et bundle verts après changement.

## Lot 3 — notifier ou non les éléments masqués (2026-10-29)
Verdict : ✅ prêt, aucun finding.

| AC | Implémenté | Test | Statut |
|---|---|---|---|
| AC43, AC45, AC46 | `NotificationGate.filter(_:prefs:now:)` option active | NotificationGateTests.defaultNotifiesHiddenItems | ✅ |
| AC49 | décodage tolérant, défaut `true` | PreferencesTests.legacyJSONDecodesWithDefaults | ✅ |
| AC50–AC52 | `DisplayFilter.hides(event)` | NotificationGateTests.disabledDropsOnlyHiddenItems | ✅ |
| AC53 | filtre appliqué après le diff, baseline intacte | NotificationGateTests.noCatchUpWhenItemBecomesVisible (diff réel sur 4 snapshots) | ✅ |
| AC54 | règles = filtres actifs uniquement | NotificationGateTests.draftsNotifiedWhenDraftFiltersOff | ✅ |
| UC14 UI | toggle General › Panel, textes States / « N hidden » | recette | à vérifier |

Points vérifiés :
- Panneau et notifications partagent `DisplayFilter` : `PanelState.make` refactoré, tests PanelState existants inchangés et verts (non-régression).
- Sourdine prioritaire (NotificationGateTests.muteStillWins) ; tags de titre hors règle.
- Mutation mentale : ignorer `notifyHiddenItems` → `disabledDropsOnlyHiddenItems` échoue ; filtrer dans le diff au lieu de la porte → `noCatchUpWhenItemBecomesVisible` échoue (rattrapage).
- Seul appel restant au filtre de sourdine seul : interne à la nouvelle porte (`grep`), `AppModel.handle` passe bien par `prefs`.
- Commandes : `swift test` 80/80 · `swift-format lint --strict` 0 · `swift build` OK · bundle + install OK, app relancée.
