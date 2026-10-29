# ADO Notifier

App macOS barre de menus (usage perso) : PRs à relire, mes PRs, work items assignés sur Azure DevOps cloud, changement d'état en un clic, notifications système.

Specs : `docs/features/ado-menubar-notifier/` (refinement, design, plan).

## Installation
1. Télécharger `ADO-Notifier-<version>.dmg` depuis les [Releases](https://github.com/Playdric/AzureDevopsNotifier/releases).
2. Ouvrir le dmg, glisser **ADO Notifier** dans **Applications**.
3. Premier lancement : l'app n'est pas notarisée par Apple, macOS la bloque. Réglages Système › Confidentialité et sécurité › **Ouvrir quand même**. Ou :
   ```sh
   xattr -dr com.apple.quarantine "/Applications/ADO Notifier.app"
   ```

Requiert macOS 26+ (Apple Silicon ou Intel).

## Développement

### Prérequis
- macOS 26+, Xcode 27 / Swift 6.
- PAT Azure DevOps avec les scopes : **Code (Read)**, **Work Items (Read & Write)**, **Project and Team (Read)**.

### Commandes
```sh
swift test                                        # tests
swift test --skip KeychainStoreTests              # sans le trousseau (session verrouillée / CI)
xcrun swift-format lint --strict -r Sources Tests # lint
swift build                                       # build debug
scripts/bundle.sh                                 # build/ADO Notifier.app signé
scripts/install.sh                                # copie dans ~/Applications
scripts/dmg.sh                                    # build/ADO-Notifier-<version>.dmg
```

### Publier une release
Version lue dans `Resources/Info.plist` (`CFBundleShortVersionString`, à incrémenter avec `CFBundleVersion`).
```sh
scripts/dmg.sh --publish                          # dmg + release GitHub v<version>
```
Ou pousser un tag `v<version>` : le workflow `.github/workflows/release.yml` build et publie le dmg.
Lancer l'app via le bundle (`open "build/ADO Notifier.app"`) : notifications, Keychain et Launch at login exigent un `.app`.

## PAT et Keychain
Le PAT est saisi dans l'app et écrit par l'app dans le trousseau (service `com.cedricnanteau.ado-notifier`, compte = URL de l'org, non synchronisé iCloud). Ne pas le créer avec `security add-generic-password` : l'entrée ferait confiance à `/usr/bin/security`, lisible sans invite par n'importe quel script.

### Certificat de signature local (recommandé)
Signée ad-hoc, l'app change d'identité à chaque build et le trousseau redemande l'accès au PAT. Pour l'éviter :
1. Trousseaux d'accès › Assistant de certification › Créer un certificat… — nom `ADO Notifier Local`, type d'identité *Racine auto-signée*, type de certificat *Signature de code*.
2. `CODESIGN_IDENTITY="ADO Notifier Local" scripts/bundle.sh`

## Désinstaller
Supprimer l'app, l'entrée trousseau `com.cedricnanteau.ado-notifier`, puis `defaults delete com.cedricnanteau.ado-notifier`.

## Licence
MIT — voir [LICENSE](LICENSE).
