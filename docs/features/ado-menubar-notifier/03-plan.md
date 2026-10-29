# ADO Menu Bar Notifier — Plan

## Design retenu
Option B — popover à sections empilées (`design/option-b.html`) + écrans communs (`design/shared.html`, onglet `Titles` inclus). Contrat UI : `02-design.md`.

## Résumé de l'approche
Projet greenfield en **Swift Package** : une lib `ADOCore` (toute la logique, sans dépendance UI, testée à fond) et un exécutable `ADONotifier` (SwiftUI, couche mince). Un script assemble le bundle `.app` (Info.plist `LSUIElement`) et le signe.
Le polling produit un `Snapshot` immuable. Un `EventDiffer` pur compare l'ancien et le nouveau snapshot → événements notifiables, filtrés par la sourdine. Un `PanelState` pur dérive de l'état (icône, bandeaux, sections) ce que les vues affichent.
Aucune dépendance tierce.

## Toolchain constatée
- Swift 6.4, Xcode 27.0, macOS 26.6.2 (arm64). `swift-format` disponible via `xcrun`. Pas de xcodegen / tuist / swiftlint.
- **Aucune identité de signature** (`security find-identity -p codesigning -v` → 0).

## Décisions techniques
| Décision | Choix | Alternative écartée | Raison |
|---|---|---|---|
| Structure projet | `Package.swift` : lib `ADOCore` + exécutable `ADONotifier` + `ADOCoreTests` | `.xcodeproj` | pbxproj illisible en review, pas de générateur installé ; Xcode 27 ouvre le Package directement |
| Bundle `.app` | `scripts/bundle.sh` : `swift build -c release` → `build/ADO Notifier.app` (Info.plist, binaire, icône), `codesign` | Target app Xcode | Requis pour notifications, `SMAppService`, Keychain, `LSUIElement` ; reste scriptable |
| Signature | `CODESIGN_IDENTITY` si défini, sinon ad-hoc (`-`). Doc README : créer un certificat auto-signé « ADO Notifier Local » (Trousseaux › Assistant de certification › Signature de code) | Ad-hoc seul | Signature ad-hoc = hash différent à chaque build → le Keychain redemande l'accès au PAT après chaque rebuild. Un certificat stable garde l'ACL |
| Framework de test | Swift Testing (`import Testing`, `@Test`, `#expect`) | XCTest | Standard Swift 6, paramétrage natif des cas (`arguments:`) |
| UI | SwiftUI `MenuBarExtra(.window)`, `Settings` scene, `Window` setup | AppKit `NSStatusItem` + `NSPopover` | Contrat UI ; suffisant sur macOS 26 |
| État observable | `@Observable @MainActor final class AppModel` | `ObservableObject` / Combine | Idiome actuel, moins de code |
| Concurrence | `actor SyncService` + `Task` de polling ; Swift 6 strict concurrency | Timer + callbacks | Pas de data race, annulation propre |
| HTTP | `URLSession` derrière `protocol HTTPTransport` | Lib tierce | Injection d'un stub dans les tests, zéro dépendance |
| Auth | Header `Authorization: Basic base64(":" + PAT)` | OAuth | Hors périmètre |
| Identité utilisateur | `GET {org}/_apis/connectionData` → `authenticatedUser.id/providerDisplayName` | `profiles/me` (vssps) | Pas de scope supplémentaire, même hôte |
| Version API | `api-version=7.1` (comments : `7.1-preview.4`) | — | Version GA courante |
| PRs | Par projet suivi : `git/pullrequests?searchCriteria.status=active&searchCriteria.reviewerId={me}` puis `…creatorId={me}` | Requête org-wide | Endpoint par projet stable ; filtre client « reviewer direct » : `reviewers[].id == me && !isContainer` (AC5) ; PR créée par moi exclue de To Review |
| Activité sur mes PRs | `…/pullRequests/{id}/threads` pour chaque PR de My PRs, à chaque cycle | Service hooks / webhooks | Pas de serveur ; volume faible (mes PRs actives) |
| Votes | `reviewers[].vote` (10, 5, 0, -5, -10) diffé entre cycles | Threads système de vote | Déjà dans la réponse liste, 0 requête en plus |
| Work items | WIQL org (`POST {org}/_apis/wit/wiql`) : `[System.AssignedTo] = @Me AND [System.TeamProject] IN (…) AND [System.State] NOT IN (<noms Completed/Removed dans tous les types>)` → `POST _apis/wit/workitemsbatch` (≤ 200 ids/lot) → filtre client exact par catégorie du type | Filtre client seul | Évite de rapatrier des milliers de WI fermés ; le filtre client couvre les noms ambigus selon le type (AC24) |
| États par type | `GET {org}/{project}/_apis/wit/workitemtypes` (états, catégorie, couleur du type) ; cache par projet, rafraîchi au lancement, toutes les heures et à l'ouverture de Settings | Appel par WI | Quota ADO (AC23, couleurs type WI du contrat UI) |
| Commentaires WI | Champ `System.CommentCount` diffé ; s'il augmente → `GET …/workItems/{id}/comments?$top=5`, auteur ≠ moi | Comments de tous les WI à chaque cycle | 1 requête seulement quand il y a du nouveau |
| Changement d'état | `PATCH {org}/_apis/wit/workitems/{id}` JSON Patch `/fields/System.State` | — | Message d'erreur ADO (`message`) remonté tel quel (AC8) |
| Baseline | Le 1er snapshot réussi = baseline, aucune notification. En erreur : snapshot précédent conservé, pas de diff. Au retour : diff vs **dernier snapshot réussi** | Diff vs snapshot vide | AC9, AC17 : pas de rafale ni de faux « nouveau » |
| Nouvel élément | Ses commentaires / votes existants sont absorbés en baseline à sa 1re apparition | Les notifier | Sinon une PR ou un WI fraîchement apparu notifie tout son historique |
| Sourdine | Le diff tourne toujours ; seuls les événements produits sont filtrés par le `NotificationGate` | Suspendre le diff | AC25/26 sans logique de rattrapage |
| Persistance réglages | `Preferences: Codable` → JSON dans `UserDefaults` (org, projets, intervalle, états masqués, tags, sourdine, sections repliées) | Fichier plist maison | Simple ; aucun secret dedans |
| PAT | `KeychainStore` (Security framework) : générique, service `com.cedricnanteau.ado-notifier`, account = URL org, `WhenUnlockedThisDeviceOnly`, non synchronisable | CLI `security`, fichier | Décision de la phase design |
| Point « nouveau » | `seenIDs` en mémoire, mis à jour à la fermeture du panneau | Persisté | Redémarrage = nouvelle baseline (refinement) |
| Launch at login | `SMAppService.mainApp.register()/unregister()` | LaunchAgent plist | API officielle |
| Veille | `NSWorkspace.didWakeNotification` → refresh immédiat + réévaluation de la sourdine | — | Cas limites veille et fin de sourdine |
| Ouverture des liens | `NSWorkspace.shared.open(url)` | — | Navigateur par défaut (Firefox) |

## Fichiers impactés (tous à créer)
- `Package.swift` — targets `ADOCore`, `ADONotifier`, `ADOCoreTests` ; macOS 26 ; Swift 6.
- `Resources/Info.plist` — `CFBundleIdentifier=com.cedricnanteau.ado-notifier`, `LSUIElement=YES`, version.
- `scripts/bundle.sh` — build release + assemblage `.app` + codesign.
- `scripts/install.sh` — copie dans `~/Applications`.
- `.swift-format` — config lint.
- `README.md` — build, installation, scopes du PAT, certificat de signature local.
- `Sources/ADOCore/`
  - `Models/` — `Identity`, `Project`, `PullRequest` (+ `Reviewer`, `Vote`), `PRThread`, `WorkItem`, `WorkItemType` (+ `StateDef`, `StateCategory`), `Snapshot`.
  - `Config/OrgURL.swift` — parse/normalise `dev.azure.com/<org>` et `<org>.visualstudio.com`.
  - `Config/WebLinks.swift` — URLs web PR / WI.
  - `Config/Preferences.swift` + `PreferencesStore.swift` (UserDefaults injectable).
  - `Secrets/SecretStore.swift` (protocole) + `KeychainStore.swift`.
  - `API/HTTPTransport.swift`, `API/ADOClient.swift`, `API/ADOError.swift`, `API/DTOs.swift`.
  - `Sync/SnapshotFetcher.swift` — assemble un `Snapshot` à partir du client.
  - `Sync/EventDiffer.swift` — `(old, new, me) -> [NotifiableEvent]`.
  - `Sync/SyncService.swift` — actor : boucle de polling, refresh manuel, intervalle, statut, baseline.
  - `Domain/StateMenu.swift` — états proposés pour un WI ; `StateCatalog` (union des noms + catégorie pour Settings).
  - `Domain/TitleCleaner.swift` — nettoyage des tags ; `TagCatalog` (détection + fusion avec les tags connus).
  - `Domain/Mute.swift` — `MuteState`, presets (1 h, demain 9:00, date, indéfini), `NotificationGate`.
  - `Domain/NotificationContent.swift` — titre/corps/URL par événement (titres nettoyés).
  - `Presentation/PanelState.swift` — icône barre de menus, bandeaux, sections, plafond 50, points « nouveau ».
- `Sources/ADONotifier/`
  - `ADONotifierApp.swift` — `@main`, `MenuBarExtra`, `Settings`, `Window("Set Up")`.
  - `AppModel.swift` — orchestre sync, prefs, keychain, notifications, changements d'état (pending / erreur par WI).
  - `Panel/` — `PanelView`, `SectionHeader`, `PRRow`, `WIRow`, `StatePill`, `VoteSummary`, `DraftBadge`, `NewDot`, `StatusBanner`, `InlineRowError`, `PanelFooter`, `MuteMenu`, `MenuBarLabel`.
  - `Setup/SetupWindow.swift` — 2 étapes Connect → Projects.
  - `Settings/` — `GeneralSettingsView`, `AccountSettingsView`, `ProjectsSettingsView`, `TitlesSettingsView`, `StatesSettingsView`.
  - `System/NotificationService.swift` (UNUserNotificationCenter + délégué de clic), `System/LaunchAtLogin.swift`, `System/WakeObserver.swift`.
- `Tests/ADOCoreTests/` — un fichier par module + `Fixtures/*.json` (réponses ADO anonymisées) + `StubTransport.swift`.

## Réutilisation
Projet vide : rien à réutiliser dans le dépôt. Composants système imposés par le contrat UI (`MenuBarExtra`, `Menu`, `Form(.grouped)`, `Toggle`, `Picker`, `DatePicker`, `ProgressView`, `SecureField`, `UNUserNotificationCenter`, `SMAppService`, `NSWorkspace`). La logique de `cleanTitle` / `detectTags` de la maquette sert de spec à `TitleCleaner` (mêmes exemples en tests).

## Étapes
1. [x] **Squelette** : `Package.swift`, `Info.plist`, `bundle.sh`, `install.sh`, `.swift-format`, app minimale (`MenuBarExtra` avec un texte), un test bidon — couvre AC19 — vérif : `swift build`, `swift test`, `scripts/bundle.sh` puis lancement : icône présente, pas d'icône Dock.
2. [x] **Config & liens** : `OrgURL`, `WebLinks`, modèles — couvre AC6 — vérif : `swift test --filter OrgURLTests|WebLinksTests`.
3. [x] **TitleCleaner + TagCatalog** — couvre AC31–AC38 + cas limites crochets — vérif : `swift test --filter TitleCleanerTests|TagCatalogTests`.
4. [x] **États** : `StateMenu`, `StateCatalog`, filtre des WI ouverts par catégorie — couvre AC7, AC21–AC24 — vérif : `swift test --filter StateMenuTests`.
5. [x] **Sourdine** : `MuteState`, presets avec `Calendar`/`now` injectés, `NotificationGate` — couvre AC25–AC27, refus d'une date passée, fin de sourdine pendant la veille — vérif : `swift test --filter MuteTests`.
6. [x] **Persistance** : `Preferences`, `PreferencesStore` (suite UserDefaults dédiée en test), `KeychainStore` (service de test unique, nettoyé) — couvre AC3, AC27, AC38 — vérif : `swift test --filter PreferencesTests|KeychainStoreTests`.
7. [x] **Client ADO** : transport, DTOs, client, mapping d'erreurs (401/203 → `.unauthorized`, erreur URL → `.network`, 4xx avec `message` → `.server(message)`) — couvre AC2, AC8 (côté client) — vérif : `swift test --filter ADOClientTests` (fixtures).
8. [x] **SnapshotFetcher** : PRs à relire (reviewer direct), mes PRs, dédoublonnage, threads, WI (WIQL + batch + filtre de catégorie), types, projets inaccessibles ignorés — couvre AC4, AC5, AC24, cas limites — vérif : `swift test --filter SnapshotFetcherTests`.
9. [x] **EventDiffer** : nouveau WI, nouvelle PR à relire, thread / réponse / vote sur mes PRs, commentaire WI, auteur = moi exclu, threads système exclus, absorption à la 1re apparition — couvre AC9–AC15 — vérif : `swift test --filter EventDifferTests`.
10. [x] **SyncService** : baseline, erreur → snapshot conservé + statut, reprise sans faux événement, intervalle (min 1 min), refresh manuel, horloge injectée — couvre AC9, AC17, AC18 — vérif : `swift test --filter SyncServiceTests`.
11. [x] **NotificationContent + PanelState** : textes des notifications (titres nettoyés, anglais), priorité de l'icône, bandeaux, vides, chargement, plafond 50, points « nouveau » — couvre AC1, AC16 (URL), AC20, AC28, AC30 (textes), AC36 (titre original conservé pour l'info-bulle) — vérif : `swift test --filter PanelStateTests|NotificationContentTests`.
12. [x] **App — panneau** : `AppModel`, vues du panneau selon `option-b.html`, pill d'état (pending / erreur inline / « No state available »), menu Mute + date, footer, clic → navigateur — couvre AC4, AC6, AC7b, AC8, AC28 — vérif : `swift build` + checklist manuelle (§ Manuel).
13. [x] **App — setup & Settings** : fenêtre Set Up 2 étapes, onglets General / Account / Projects / Titles / States, validation du PAT, au moins un projet requis, avertissement si permission notifications refusée — couvre AC1, AC2, AC3, AC29, UC10, UC12 — vérif : build + checklist.
14. [x] **App — système** : `NotificationService` (autorisation, `threadIdentifier`, clic → URL), `LaunchAtLogin`, `WakeObserver` — couvre AC16, AC29, veille — vérif : build + checklist.
15. [ ] **Recette réelle** sur l'organisation ADO perso + `swift format lint` + bundle final — tous les AC de la checklist manuelle.

## Stratégie de test
| AC | Type | Fichier test | Scénario |
|---|---|---|---|
| AC1 | unit | PanelStateTests | prefs vides → `.notConfigured`, icône estompée |
| AC2 | unit | ADOClientTests | connectionData 401 / 203 (page de login HTML) → `.unauthorized` ; le flux de setup ne sauve rien |
| AC3 | unit | KeychainStoreTests, PreferencesTests | aller-retour Keychain ; le JSON des prefs encodées ne contient pas le PAT |
| AC4 | unit | SnapshotFetcherTests | 2 projets suivis sur 3 → seuls leurs PRs/WI |
| AC5 | unit | SnapshotFetcherTests | reviewer via groupe (`isContainer`) → absent ; PR que j'ai créée et où je suis reviewer → My PRs seulement |
| AC6 | unit | WebLinksTests | URLs PR / WI, orgs `dev.azure.com` et `visualstudio.com` |
| AC7 | unit | StateMenuTests | Bug Active, masqués {Removed} → New, Resolved, Closed |
| AC7b | unit + manuel | ADOClientTests | corps du PATCH JSON Patch correct ; ligne à jour (manuel) |
| AC8 | unit + manuel | ADOClientTests | 400 TF401320 → `.server(message)` ; erreur inline (manuel) |
| AC9 | unit | EventDifferTests, SyncServiceTests | 1er cycle → 0 événement |
| AC10 | unit | EventDifferTests | WI nouveau → 1 événement ; cycle suivant identique → 0 |
| AC11 | unit | EventDifferTests | nouvelle PR, reviewer direct → 1 |
| AC12 | unit | EventDifferTests | nouveau thread / nouvelle réponse d'autrui → 1 chacun |
| AC13 | unit | EventDifferTests | commentaire de moi → 0 ; thread système → 0 |
| AC14 | unit | EventDifferTests | vote 0 → -5 → 1 événement « waiting for author » |
| AC15 | unit | EventDifferTests | CommentCount +1, auteur autre → 1 ; auteur moi → 0 |
| AC16 | unit + manuel | NotificationContentTests | userInfo contient la bonne URL ; clic ouvre le navigateur (manuel) |
| AC17 | unit | SyncServiceTests | cycle KO → snapshot conservé, statut erreur, 0 événement ; reprise → seulement les vrais changements |
| AC18 | unit | SyncServiceTests | horloge injectée : intervalle 3 min → fetch à t+3, t+6 ; valeur < 1 ramenée à 1 |
| AC19 | manuel | — | pas d'icône Dock (`LSUIElement`) |
| AC20 | unit | PanelStateTests | PR à relire ou WI non vu → icône `.activity(count)` |
| AC21 | unit | StateMenuTests | « Blocked » masqué → absent pour tous les types qui l'ont |
| AC22 | unit | PanelStateTests | état courant masqué toujours affiché sur la ligne |
| AC23 | unit | StateMenuTests | PBI Scrum vs Bug Agile → chacun ses états |
| AC24 | unit | SnapshotFetcherTests | WI dans un état Completed/Removed de son type → exclu |
| AC25 | unit | MuteTests | sourdine active → gate bloque, snapshot quand même à jour |
| AC26 | unit | MuteTests, SyncServiceTests | événement pendant la sourdine → jamais émis ; après l'échéance → émis |
| AC27 | unit | PreferencesTests | sourdine persistée et relue |
| AC28 | unit | PanelStateTests | sourdine → icône `.muted` + bandeau « Muted until … » |
| AC29 | manuel | — | option cochée au setup ; reboot → app lancée |
| AC30 | unit + manuel | NotificationContentTests, PanelStateTests | chaînes en anglais ; relecture des vues |
| AC31 | unit | TagCatalogTests | `[Backend]`, `[Hotfix]` détectés avec leurs comptes |
| AC32 | unit | TitleCleanerTests | `[Hotfix]` masqué → `[Backend] Fix [SSO] login` |
| AC33 | unit | TitleCleanerTests | hideAll → `Fix login`, y compris un tag inconnu |
| AC34 | unit | TitleCleanerTests | `[HOTFIX]`, `[ Hotfix ]` matchent `hotfix` |
| AC35 | unit | TitleCleanerTests | `[WIP]` seul → titre original |
| AC36 | unit + manuel | PanelStateTests | la ligne garde `originalTitle` ; `.help` affiché (manuel) |
| AC37 | unit | TagCatalogTests | nouveau tag → ajouté, non masqué |
| AC38 | unit | TagCatalogTests, PreferencesTests | tag absent puis revenu → choix conservé |
| Cas limites | unit | divers | `[WIP Fix`, `[[x]]`, `array[0]`, séparateurs de bord, projet inaccessible, état courant inconnu du process, même nom d'état dans des catégories différentes |

### Manuel (étape 15, organisation ADO réelle)
AC19, AC29, rendu du panneau vs `option-b.html` (clair / sombre), AC7b/AC8 sur un vrai WI, AC16 clic notification, permission refusée, veille / réveil, 100+ éléments fluides, VoiceOver sur les boutons-icônes.

## Commandes
- tests : `swift test`
- lint : `xcrun swift-format lint --strict -r Sources Tests`
- build : `swift build` (debug) · `scripts/bundle.sh` (release + `.app` signé) · `scripts/install.sh`

## Lot 2 — retours de recette (2026-10-28)
Couvre AC39–AC48 (refinement UC10 étapes 5-6, UC13, fermeture du panneau).

| Décision | Choix | Alternative écartée | Raison |
|---|---|---|---|
| Fermer le panneau | `@Environment(\.dismiss)` dans le contenu du `MenuBarExtra`, appelé avant `openSettings` / `openWindow` / `NSWorkspace.open` ; centralisé dans un helper `PanelActions` | `NSApp.keyWindow?.close()` | API SwiftUI officielle pour fermer la fenêtre du `MenuBarExtra` |
| Masquage par état dans la liste | `Preferences.listHiddenStates: Set<String>` appliqué dans `PanelState.make` (affichage seul) ; le snapshot et `EventDiffer` restent intacts | Filtrer dans `SnapshotFetcher` | Notifications inchangées (AC43) ; réapparition immédiate si l'état change (AC44) |
| Drafts | `Preferences.hideDraftsToReview` / `hideDraftsMine` appliqués dans `PanelState.make` | Filtre côté API | Même raison ; badge calculé sur les lignes visibles (AC45) |
| Largeur / wrap | `Preferences.panelWidth: PanelWidth` (enum `standard=380`, `wide=480`, `extraWide=600`) + `wrapTitles: Bool` | Redimensionnement à la souris | Non supporté par `MenuBarExtra(.window)` |
| « N hidden » | `PanelSection.hiddenCount` | — | Explique une section vide ou incomplète |
| Décodage prefs | `init(from:)` tolérant avec `decodeIfPresent` + valeurs par défaut | Migration versionnée | Les prefs déjà enregistrées pendant la recette restent lisibles |

### Étapes
16. [x] **Prefs** : nouveaux champs + décodage tolérant — couvre AC47 (persistance) — vérif : `swift test --filter PreferencesTests` (ancien JSON sans les champs → valeurs par défaut).
17. [x] **PanelState** : filtres liste par état + drafts, `hiddenCount`, badge sur lignes visibles — couvre AC42, AC44, AC45, AC46 — vérif : `swift test --filter PanelStateTests`.
18. [x] **Notifications inchangées** : test de non-régression, le diff ignore les filtres d'affichage — couvre AC43, AC45 — vérif : `swift test --filter PanelStateTests|EventDifferTests`.
19. [x] **UI** : section Panel dans General, 2 colonnes + All/None dans States, largeur et wrap appliqués, « N hidden », fermeture du panneau — couvre AC39, AC40, AC41, AC47, AC48 — vérif : build + recette.

### Tests ajoutés
| AC | Type | Fichier test | Scénario |
|---|---|---|---|
| AC42 | unit | PanelStateTests | `listHiddenStates = [Resolved]` → WI Resolved absent, `hiddenCount == 1`, badge sans lui |
| AC43 | unit | PanelStateTests | snapshot conservé intact + diff produit l'événement malgré le filtre |
| AC44 | unit | PanelStateTests | même WI passé à Active → visible |
| AC45 / AC46 | unit | PanelStateTests | drafts filtrés par section, badge = lignes To Review visibles |
| AC47 | unit | PreferencesTests | aller-retour largeur ; ancien JSON → Standard |
| AC39–AC41, AC48 | manuel | — | recette |

## Lot 3 — notifier ou non les éléments masqués (2026-10-29)
Couvre UC14, AC49–AC54 (+ AC43, AC45, AC46 reformulés).

| Décision | Choix | Alternative écartée | Raison |
|---|---|---|---|
| Où filtrer | `NotificationGate.filter(_:prefs:now:)` : sourdine puis éléments masqués ; `AppModel.handle` l'appelle | Filtrer dans `EventDiffer` / `SnapshotFetcher` | Le diff reste complet (baseline correcte, pas de rattrapage) ; un seul point de décision testable |
| Règles « masqué » | `DisplayFilter` (ADOCore) : `hides(review:)`, `hides(mine:)`, `hides(_ wi:)`, `hides(_ event:)` ; réutilisé par `PanelState.make` | Dupliquer les conditions | Le panneau et les notifications ne peuvent pas diverger |
| État évalué | celui porté par l'événement (snapshot courant) | état au cycle précédent | « Au moment de l'événement » (UC14) |
| Défaut | `notifyHiddenItems = true`, décodage tolérant | false | Comportement validé en recette conservé (AC49) |

### Étapes
20. [x] **ADOCore** : `Preferences.notifyHiddenItems` + décodage ; `DisplayFilter` ; `PanelState.make` passe par `DisplayFilter` ; `NotificationGate.filter(_:prefs:now:)` — couvre AC49–AC54 — vérif : `swift test --filter PreferencesTests|NotificationGateTests|PanelStateTests`.
21. [x] **App** : `AppModel.handle` utilise la nouvelle porte ; toggle General › Panel ; textes States et « N hidden » — couvre UC14 UI — vérif : build + recette.

### Tests ajoutés
| AC | Type | Fichier test | Scénario |
|---|---|---|---|
| AC49 | unit | PreferencesTests.legacyJSONDecodesWithDefaults | ancien JSON → `notifyHiddenItems == true` |
| AC43, AC45, AC46 | unit | NotificationGateTests | option active → événements des éléments masqués conservés |
| AC50 | unit | NotificationGateTests | review draft coupée, non draft conservée |
| AC51 | unit | NotificationGateTests | commentaire + vote sur ma PR draft coupés |
| AC52 | unit | NotificationGateTests | WI Resolved assigné + commenté coupés |
| AC53 | unit | NotificationGateTests | diff réel : PR draft → publiée, aucun `reviewRequested` rejoué ; nouveau commentaire ensuite notifié |
| AC54 | unit | NotificationGateTests | filtres drafts inactifs → drafts notifiées même option désactivée |
| — | unit | PanelStateTests (existants) | non-régression après passage par `DisplayFilter` |

## Écarts constatés en dev
- Lint : `swift-format format -i` appliqué avant `lint --strict` (config `.swift-format`, ligne 120).
- Étape 15 (recette sur org réelle) : à faire par l'utilisateur — nécessite PAT perso. Smoke test fait : bundle lancé, process `UIElement` (AC19).

## Risques & mitigations
- **Keychain + signature ad-hoc** : invite d'accès après chaque rebuild → certificat auto-signé local (README) ; `CODESIGN_IDENTITY` dans `bundle.sh`.
- **Notifications sans bundle** : `UNUserNotificationCenter` plante si lancé hors `.app` (`swift run`) → `NotificationService` désactivé si `Bundle.main.bundleIdentifier == nil` ; tester l'app via `bundle.sh`.
- **Quotas ADO / rate limit** : ~2 requêtes par projet + 1 par PR à moi + 2 WI par cycle ; respect de `Retry-After` / 429 → cycle sauté ; cache des types.
- **Réponse 203 HTML** quand le PAT est invalide (ADO redirige vers le login) → traitée comme `.unauthorized`.
- **API comments en preview** (`7.1-preview.4`) peut changer → isolée dans `ADOClient`, fixture dédiée.
- **Sécurité** : PAT jamais loggé (pas de `print` des requêtes ; header construit à la volée) ; HTTPS uniquement ; `OrgURL` refuse les autres hôtes.
- **Volume** : `List` SwiftUI paresseuse ; plafond 50 lignes/section.
- **Rollback** : app autonome ; désinstaller = supprimer le `.app`, l'entrée Keychain et le domaine `defaults delete com.cedricnanteau.ado-notifier`.
