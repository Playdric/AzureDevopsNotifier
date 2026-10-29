# Statut CI des PRs — Refinement

## Contexte & objectif
Plusieurs pipelines de CI (build validation policies Azure) tournent en parallèle sur chaque PR. Aujourd'hui l'app ne montre rien : il faut ouvrir la PR dans le navigateur pour savoir si la CI a échoué ou si la PR est mergeable.
Objectif : voir d'un coup d'œil l'état CI de chaque PR (y compris combien de pipelines échouent), être notifié quand un pipeline de mes PRs échoue, et quand une de mes PRs devient prête à merger.

## Acteurs
- Utilisateur (seul, usage perso) : consulte le panel, reçoit les notifications, active/désactive les notifs CI dans Settings.

## Définitions
- **Pipeline CI** : évaluation d'une policy de type *Build validation* sur la PR (source : policy evaluations ADO). Statuts PR externes (API statuses) hors périmètre.
- **Requis / optionnel** : policy bloquante (`isBlocking`) ou non.
- **État d'un pipeline** : en attente/en cours · réussi · échoué · expiré (à relancer) · non applicable.
- **Prête à merger** : PR non draft **et** toutes les policies bloquantes approuvées (CI requise verte, reviewers requis, work item lié, commentaires résolus…) — équivalent du bouton *Complete* actif dans ADO. Exception : policy *Require a merge strategy* ignorée (évaluée sur la stratégie choisie à la complétion, `rejected` avant ; constaté sur PR réelle 2026-10-29).

## Cas d'usage
### UC1 — Voir l'état CI d'une PR dans le panel
- **Acteur** : utilisateur
- **Préconditions** : PR affichée dans *My PRs* ou *To Review*, au moins une build validation policy évaluée.
- **Scénario nominal** : 1. Ouvre le panel. 2. Chaque PR montre une icône CI agrégée (échec / en cours / succès). 3. Si plusieurs pipelines échouent, le nombre d'échecs est visible. 4. Survol → détail : nom et état de chaque pipeline, requis/optionnel.
- **Variantes** : aucune build policy → pas d'icône. Échec uniquement sur pipelines optionnels → icône d'échec atténuée (distincte d'un échec requis).
- **Postconditions** : aucune.

### UC2 — Notification d'échec d'un pipeline (My PRs)
- **Acteur** : système → utilisateur
- **Préconditions** : PR dans *My PRs*, déjà présente au sync précédent, toggle « CI failed » activé.
- **Scénario nominal** : 1. Sync. 2. Un pipeline passe d'un état non-échec à échoué. 3. Notification : nom du pipeline (+ « optional » si non bloquant), titre de la PR. Clic → ouvre la PR.
- **Variantes** : 2 pipelines échouent au même sync → 2 notifications, groupées par PR. Pipeline relancé qui échoue à nouveau (passé par en cours) → nouvelle notification.
- **Postconditions** : icône du panel à jour.

### UC3 — Notification « prête à merger » (My PRs)
- **Acteur** : système → utilisateur
- **Préconditions** : PR dans *My PRs*, déjà présente au sync précédent et non prête, toggle « Ready to merge » activé.
- **Scénario nominal** : 1. Sync. 2. La PR devient prête à merger. 3. Notification « Ready to merge » + titre PR. Clic → ouvre la PR.
- **Variantes** : PR redevient non prête (nouveau push, vote retiré) puis prête à nouveau → nouvelle notification.

### UC5 — Voir qu'une de mes PRs est prête à merger
- **Acteur** : utilisateur
- **Préconditions** : PR dans *My PRs*, non draft, toutes policies bloquantes approuvées.
- **Scénario nominal** : panel → badge `READY` avant le titre ; tooltip CI se termine par « Ready to merge ».

### UC4 — Activer / désactiver les notifs CI
- **Acteur** : utilisateur
- **Scénario nominal** : Settings → deux toggles « CI failed » et « Ready to merge », activés par défaut. Désactivé → aucune notif de ce type ; icône du panel inchangée.

## Critères d'acceptation
- [ ] AC1 — Given PR avec 3 build policies dont 2 échouées (requises), When panel affiché, Then 3 pastilles dont 2 rouges ; VoiceOver « CI: 2 of 3 failed ».
- [ ] AC2 — Given PR avec builds en cours et aucun échec, Then pastilles en anneau (bleu en cours, gris en file). Given toutes builds réussies, Then pastilles vertes.
- [ ] AC3 — Given PR sans build policy, Then aucune icône CI.
- [ ] AC4 — Given seul un pipeline optionnel échoué, Then pastille rouge atténuée (opacité réduite) distincte d'un échec requis.
- [ ] AC5 — Given survol de l'icône, Then liste nom + état + requis/optionnel de chaque pipeline.
- [ ] AC6 — Given icône sur PR *To Review*, Then mêmes règles d'affichage qu'en *My PRs*, et aucune notification CI.
- [ ] AC7 — Given ma PR connue, pipeline « Build » passe de en cours à échoué, When sync, Then 1 notification mentionnant « Build » et le titre PR.
- [ ] AC8 — Given 2 pipelines passent en échec au même sync, Then 2 notifications avec même threadID PR.
- [ ] AC9 — Given pipeline déjà échoué au sync précédent et toujours échoué, Then aucune notification.
- [ ] AC10 — Given pipeline optionnel passe en échec, Then notification mentionnant « optional ».
- [ ] AC11 — Given ma PR non prête passe prête (toutes policies bloquantes approuvées, non draft), Then 1 notification « Ready to merge ».
- [ ] AC12 — Given PR prête au sync précédent et toujours prête, Then aucune notification.
- [ ] AC13 — Given PR apparue dans ce sync (ou premier sync au lancement), Then aucune notification CI (état absorbé), icône affichée.
- [ ] AC14 — Given PR draft avec toutes policies OK, Then pas de notification ready.
- [ ] AC15 — Given toggle « CI failed » désactivé, Then aucune notif d'échec ; idem toggle « Ready to merge ». Icônes inchangées.
- [ ] AC17 — Given ma PR prête à merger (non draft), Then badge READY affiché ; Given PR draft ou non prête, Then pas de badge ; jamais sur To Review.
- [ ] AC16 — Given erreur API sur les policies d'une PR, Then sync reste OK, PR affichée avec le dernier état CI connu (aucun si jamais chargé), aucune notif fausse ni perdue au sync suivant.

## Cas limites
- Build expiré (policy à relancer) : traité comme « en attente », pas un échec.
- Policy « non applicable » (filtre de chemins) : ignorée.
- Plusieurs policies pour le même pipeline (branches) : chaque évaluation compte séparément, nom = nom affiché de la policy.
- Filtre « notifier éléments masqués » existant : s'applique aussi aux notifs CI.
- Mute existant sur une PR : s'applique aussi aux notifs CI.

## Hors périmètre
- Statuts PR externes (GitHub Actions, Jenkins via API statuses).
- Relancer un pipeline depuis l'app.
- Logs / détail des étapes d'un pipeline.
- Notifications CI pour les PRs *To Review*.
- Icône CI dans la barre de menus (icône globale).

## Contraintes non fonctionnelles
- 1 appel API supplémentaire par PR et par sync (policy evaluations) — acceptable pour volume perso ; à confirmer au plan.
- Scope PAT : policy evaluations nécessite potentiellement *Project and Team (Read)* / *Code (Read)* — à vérifier au plan, README à mettre à jour si nouveau scope.
- Accessibilité : icône avec label VoiceOver (état + nombre d'échecs).

## Impact UI
**oui** — ligne PR (pastilles CI par pipeline + tooltip, badge READY en My PRs) dans *My PRs* et *To Review* ; Settings (2 toggles).

## Questions ouvertes
- (aucune — rendu visuel exact tranché en phase design)
