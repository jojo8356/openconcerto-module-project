# Changelog

> **La version qui compte pour OpenConcerto est celle de `module.properties`**
> (installée en `1.2` ; prochaine version publiée : `1.5`, les tags `v1.1` à
> `v1.4` étant déjà pris). C'est elle que le client compare à la base pour
> savoir s'il doit rejouer l'installation SQL du module, et elle ne doit jamais
> redescendre. Les sections ci-dessous sont datées ; la version publiée est
> précisée dans le titre des sections de release.
> Voir `docs/release-process.md`.

## 2026-10-29 — Colonne « Affaire » dans le tableau des lignes

### Fixed

- **« Dans le tableau je ne vois toujours pas l'affaire »** (détail d'une
  commande fournisseur `11870-PO-007-Avt1`). Le champ Affaire de l'en-tête est
  actif et renseigné, mais **OpenConcerto n'affiche l'affaire nulle part dans le
  tableau des lignes** : ce n'était ni un droit ni une donnée manquante, mais une
  fonctionnalité absente du cœur. Une colonne **Affaire**, en lecture seule, est
  désormais ajoutée dans les tableaux de lignes des documents, **achats et
  ventes** (commande/facture fournisseur, bon de réception, demande de prix,
  commande client, facture de vente, devis, avoirs, bon de livraison).
  - valeur = **numéro de l'affaire** (`11870`), jamais recasé ; à défaut le nom,
    puis `Affaire 145` ; case vide si l'affaire n'est pas renseignée ;
  - **la ligne d'abord** (`ID_AFFAIRE` de la ligne s'il existe), **sinon le
    document parent** (`COMMANDE`, `FACTURE_FOURNISSEUR`, `COMMANDE_CLIENT`...) :
    en 1.7.6 les tables de lignes n'ont pas le champ, seul l'en-tête l'a ;
  - colonne placée **juste après « Désignation »**, titre `Affaire`, texte noir,
    lecture seule ;
  - aucune modification du jar OpenConcerto (API publiques
    `AbstractArticleItemTable`, `RowValuesTableModel`, `XTableColumnModel`) ;
  - installation idempotente à l'affichage, désactivable par
    `-Dproject.itemAffair=false`.

### Added

- `ItemAffairColumnRules` : règles pures et testables (quels tableaux, d'où vient
  la valeur, format du libellé, position de la colonne).
- `ItemTableAffairColumn` : application à l'interface, sans Swing dans les règles.
- `ItemAffairColumnRulesTest` : **110 vérifications** (toutes vertes en CI).
- La CI vérifie désormais la présence des deux classes de la colonne dans le jar.

## 2026-10-29 — « Aide > Diagnostic affaire » : l'entrée est enfin dans le menu

### Fixed

- **L'entrée de menu n'apparaissait pas.** `MainFrame.addMenuItem` exige un
  chemin d'un nombre **pair** d'éléments (menu puis groupe) :
  `addMenuItem(action, "Aide")` levait `IllegalArgumentException` (« Path should
  be of the form menu/group/menu/group/... »), exception avalée par le `catch`.
  Le module repère désormais le menu par son **texte affiché** dans la `JMenuBar`
  (casse, accents et espaces tolérés ; correspondance partielle pour les clients
  traduits), puis ajoute l'élément dans ce `JMenu` ; repli sur
  `addMenuItem(menu, groupe)` avec un chemin toujours valide.
- Journalisation explicite de l'emplacement trouvé, ou de la liste des menus si
  le repérage échoue.

### Added

- `ProjectMenuSupport` : règle pure et testable (sans Swing) du repérage de menu
  et des chemins d'insertion valides.
- `ProjectMenuSupportTest` : **27 tests** — casse/accents/espaces, menu absent,
  `null`, correspondance partielle, chemins pairs, et **refus du chemin à un
  seul élément** (la régression constatée).

## 2026-10-28 — `scripts/oc-psql.sh` : SQL sur la base Docker sans `.env`

### Added

- **`scripts/oc-psql.sh`** : ouvre `psql` sur la base OpenConcerto en parlant
  **directement au conteneur**, sans `docker compose`. Corrige les deux erreurs
  qui bloquaient : `no configuration file provided` (le `docker-compose.yml` est
  dans `docker/openconcerto-1.7.6/`, pas à la racine) et
  `required variable POSTGRES_PASSWORD is missing` (`.env` non versionné).
  - détecte le conteneur (port **5433**, sinon premier conteneur
    `postgres`/`postgis`), le rôle (`POSTGRES_USER`) et la base (`POSTGRES_DB`,
    sinon l'unique base `OpenConcerto*`) ; en cas d'ambiguïté, **liste et
    s'arrête** au lieu de deviner ;
  - modes : invite interactive, `-c SQL`, `-f fichier`, `-l` (bases), `-n`
    (dry-run) ;
  - `--no-password LOGIN` et `--password LOGIN MDP` : écrit
    `Base64(SHA1(...))` dans `"Common"."USER_COMMON"."PASSWORD"`, avec la
    vérification dans la même commande ;
  - compatible `sh` (aucune dépendance côté hôte : ni bash, ni `psql`).
- `docs/psql-docker.md` : les deux messages d'erreur, leur cause, la méthode
  script, les commandes Docker équivalentes et les précautions (login unique,
  retour arrière).

### Tests

- `tests/shell/test-oc-psql.sh` : **38 contrôles, 0 échec**, sans Docker (faux
  `docker` en tête de `PATH`). Couvre la détection par port puis par image,
  l'absence de conteneur, `POSTGRES_DB` disparu après restauration, plusieurs
  bases (refus explicite), `-d` forcé, `--no-password` (empreinte exacte de la
  chaîne vide), `--password`, `-l`, `-n`, `-f` (stdin sans TTY) et l'absence
  totale d'appel à `docker compose`.

## 2026-10-28 — Libellés automatiques : « Fournisseur », plus « FOURNISSEUR »

### Changed

- Le libellé **automatique** suit désormais la mise en forme du cœur
  d'OpenConcerto (`SQLFieldTranslator.getDefaultDesc` : `firstUpThenLow` puis
  `_` → espace) : `ID_FOURNISSEUR` donne **`Fournisseur`** (et non plus
  `FOURNISSEUR`), `ID_ETAT_AFFAIRE` → `Etat affaire`,
  `ID_FACTURE_FOURNISSEUR` → `Facture fournisseur`. Nouvelle fonction publique
  `ColumnLabelRules.firstUpThenLow`.
- Conséquence dans l'ERP : une liste qui affiche encore un en-tête technique
  (`ID_CLIENT`) affiche maintenant `Client`, comme les en-têtes natifs ; plus
  aucune capitale dans les libellés automatiques.
- Les règles **explicites** saisies par l'utilisateur restent inchangées, casse
  comprise : une règle `FOURNISSEURES` reste affichée `FOURNISSEURES` tant
  qu'elle n'est pas corrigée.

### Tests

- `ColumnLabelRulesTest` : **58 tests** — nouveau
  `testAutomaticLabelUsesCoreTitleStyle` (parité avec `firstUpThenLow`, aucun
  libellé automatique en capitales).

## 2026-10-28 — Libellés : filets de sécurité dans les listes du cœur

### Fixed

- Le rendu d'en-tête pouvait être **remplacé par le cœur** après notre
  installation (les listes posent leur propre rendu à la construction) : il est
  désormais réinstallé à chaque passage (`installHeaderRenderer` vérifie que
  notre rendu est bien celui en place, au lieu de se fier à un drapeau posé une
  seule fois).
- Quand une liste **n'expose pas l'identifiant technique** de ses colonnes, la
  règle est retrouvée par son **libellé automatique** :
  `*.ID_FOURNISSEUR` → « FOURNISSEUR » correspond à l'en-tête « Fournisseur »
  (`ColumnLabelRules.ruleByAutomaticLabel`).
- Diagnostic : après chaque enregistrement, la console indique le nombre de
  règles, de colonnes rafraîchies et de **tableaux suivis**
  (`ColumnLabelUi.countManagedTables`) ; `-Dproject.labels.debug=true` trace
  chaque colonne non reconnue.

### Tests

- `ColumnLabelRulesTest` : **57 tests** (résolution par libellé automatique,
  priorité table > `*`, normalisation casse/accents/ponctuation).
- `scripts/test-mutations-colonnes.sh` : **17 contrôles** — la mutation 16
  supprime ce filet et la suite échoue.

## 2026-10-28 — Libellés : les règles s'appliquent aussi aux colonnes à libellé métier

### Fixed

- Dans **Historique affaires → Articles commandés** (et toutes les listes du
  cœur), la colonne s'affiche « Fournisseur » alors que son champ est
  `ID_FOURNISSEUR` : la règle `*.ID_FOURNISSEUR` ne s'appliquait donc jamais.
  Le module lit désormais l'identifiant technique de la colonne
  (`SQLTableModelColumn.getIdentifier()`, ex.
  `FieldPath "COMMANDE_ELEMENT"."ID_COMMANDE"."ID_FOURNISSEUR"`) et résout la
  règle sur le **champ** (`ColumnLabelRules.resolveForColumn`,
  `technicalField`, `technicalTable`).
- Ordre de priorité : `TABLE.CHAMP` > `*.CHAMP` > `TABLE.EN-TÊTE` > `*.EN-TÊTE`
  > automatique > en-tête d'origine. On peut donc aussi saisir une règle sur le
  libellé affiché (`FOURNISSEUR`).
- Le mode `AUTO` **n'écrase plus les libellés métier** : il ne simplifie que les
  en-têtes techniques (`ID_CLIENT` → `CLIENT`) ; « Fournisseur » reste
  « Fournisseur » tant qu'aucune règle ne le vise.

### Tests

- `ColumnLabelRulesTest` : **56 tests** (découpage des identifiants, y compris
  chemins de jointure, priorité des règles, non-écrasement des libellés métier).
- `scripts/test-mutations-colonnes.sh` : **16 contrôles** — mutations 14 et 15
  (règle déconnectée du champ technique, AUTO qui écrase les libellés métier)
  détectées.

## 2026-10-28 — Fermeture de l'historique : plus d'« UncaughtException »

### Fixed

- Fermer la fenêtre **Historique des affaires** pouvait afficher
  `UncaughtException … Cannot invoke "JListSQLTablePanel.removeAllTableListener()" because "this.jListePanel" is null`
  (`ProjectHistory$8.windowClosing` → `ListeHistoriquePanel.removeAllTableListener`).
  Le cœur construit ses onglets **avant** la liste de gauche : quand cette
  construction ne va pas au bout, `jListePanel` reste `null` et notre écouteur de
  fermeture propageait l'exception dans la boucle d'événements.
- Le nettoyage des écouteurs passe désormais par `HistoryPanelCleanup` : on
  vérifie que le panneau est prêt avant d'appeler le cœur, l'appel est protégé
  (`catch Throwable`), il n'a lieu qu'une fois par fenêtre et la fermeture se
  poursuit toujours. Décision tracée :
  `historique : liste de gauche non construite (jListePanel null) : nettoyage ignore`.

### Tests

- `AffairLinkSupportTest` : **38 tests** (3 nouveaux : panneau non construit,
  panneau construit, version du client sans le champ interne).
- `scripts/test-mutations-affaire.sh` : **13 contrôles** — la mutation 12 retire
  la garde et la suite échoue.

## 2026-10-28 — Libellés appliqués dans toutes les listes + filtre par colonne

### Fixed

- **Les libellés ne changeaient pas dans les listes de l'ERP** (historique des
  affaires, factures fournisseurs, articles commandés…). Les en-têtes étaient
  renommés une fois, puis perdus : les listes reconstruisent leurs colonnes à
  chaque rafraîchissement. Le libellé est désormais résolu **au moment du dessin
  de l'en-tête** (`ColumnLabelUi.installHeaderRenderer`), donc il s'applique quel
  que soit le moment où la liste se reconstruit, sans redémarrage.

### Added

- **Sélecteur de colonne dans le filtre** de l'écran de paramétrage :
  `Toutes les colonnes`, `Table`, `Colonne`, `Automatique`, `Libellé affiché`
  (`ColumnLabelRules.FILTER_CHOICES` / `filterColumnIndex`). Chercher
  `fournisseur` dans `Colonne` va beaucoup plus vite que de parcourir la liste.

### Tests

- `ColumnLabelRulesTest` : **52 tests** (correspondance sélecteur → colonne).
- `scripts/test-mutations-colonnes.sh` : 14 contrôles.
- compilation contre `OpenConcerto.jar` 1.7.6 : aucune erreur imputable au module.

## 2026-10-28 — Libellés : la règle « toutes les tables » devient visible

### Fixed

- **« Appliquer à toutes les tables (*) » semblait sans effet** : la règle `*`
  était créée (et enregistrée), mais ajoutée **en bas de la liste** — donc hors
  écran — et surtout **les lignes du tableau continuaient d'afficher le libellé
  automatique**, car l'affichage ignorait les règles `*.COLONNE`. Désormais :
  - la règle `*` est **insérée en tête de liste**, sélectionnée et amenée à
    l'écran ;
  - l'affichage du tableau applique la même résolution que les listes de l'ERP
    (règle de la table > règle `*` > automatique) : `ColumnLabelRules.resolvedLabel` ;
  - le message de confirmation indique où regarder.
- La liste est triée : règles `*` d'abord, puis tables et colonnes par ordre
  alphabétique (les tables `sauvegarde_…` ne se mélangent plus au métier).

### Tests

- `ColumnLabelRulesTest` : **51 tests** (priorité table > `*` > auto, modes
  MAPPING/OFF).
- `scripts/test-mutations-colonnes.sh` : **14 contrôles** — la mutation 13
  ignore les règles `*` à l'écran et la suite échoue.

## 2026-10-28 — Libellés : message clair et avertissement « table de sauvegarde »

### Fixed

- Le message de fin d'enregistrement laissait croire que rien n'avait été
  enregistré : il affichait « 0 colonne(s) mise(s) à jour sur ce poste ».
  Il sépare désormais les deux informations (`ColumnLabelRules.saveReport`) :
  **règles écrites en base** (partagées) et **colonnes rafraîchies sur ce poste**
  (souvent 0 quand aucune liste n'est ouverte ou n'affiche ces colonnes).
- **Avertissement sur les tables de sauvegarde** : une règle posée sur
  `sauvegarde_FACTURE_FOURNISSEUR_avant_…` ne s'affiche dans aucune liste. Le
  message cite la table et propose la règle `*`.
- Nouveau bouton **« Appliquer à toutes les tables (*) »** : crée la règle
  `*.COLONNE` à partir de la ligne sélectionnée — renommer `ID_FOURNISSEUR`
  partout en une seule opération.

### Tests

- `ColumnLabelRulesTest` : **50 tests** (détection des tables de sauvegarde,
  garde-fou contre les faux positifs type `ATTESTATION`, contenu du message).
- `scripts/test-mutations-colonnes.sh` : **13 contrôles** — mutations 11 et 12
  (avertissement supprimé, toute table vue comme une sauvegarde) détectées.

## 2026-10-28 — Libellés des colonnes : texte noir (lisibilité)

### Fixed

- La colonne **« Libellé affiché »** était en **gris italique** pour les libellés
  automatiques : trop pâle à l'écran. Tout est désormais en **noir**, seule la
  graisse distingue une règle (gras) d'un libellé automatique (normal)
  (`ColumnLabelStyle`). Les en-têtes de colonnes et le reste du tableau sont
  aussi en noir explicite, quel que soit le thème du client.

### Tests

- `ColumnLabelRulesTest` : **47 tests** (couleur noire + graisse).
- `scripts/test-mutations-colonnes.sh` : **11 contrôles** — la mutation 10 remet
  le gris pâle et la suite **échoue**.

## 2026-10-28 — Libellés des colonnes : édition directe dans le tableau

### Changed

- La case **« Libellé affiché »** n'est plus vide quand rien n'est personnalisé :
  elle montre **ce que voient les utilisateurs** (règle saisie, sinon libellé
  automatique). La colonne **Automatique** rappelle ce que donnerait la
  suppression du préfixe `ID_`.
- **Modification en direct** : double-clic sur la case (ou F2, ou frappe directe
  dans la case sélectionnée), texte pré-sélectionné, **Entrée** valide,
  **Échap** annule. Les libellés personnalisés apparaissent en **gras bleu**,
  les automatiques en *gris italique*.
- **Vider une case** (ou **Réinitialiser (libellé auto)** sur plusieurs lignes)
  revient au libellé automatique. Un texte inchangé ne crée pas de règle
  inutile : la table ne se remplit pas de centaines de règles identiques à
  l'automatique (`ColumnLabelRules.applyEdit`).
- La fermeture de la fenêtre propose d'enregistrer les modifications non
  sauvegardées (`EntryTableModel.isDirty`).
- La colonne « Aperçu » devient **« Automatique »**, et l'aide de l'écran décrit
  le double-clic.

### Tests

- `ColumnLabelRulesTest` : **45 tests** (5 nouveaux : affichage du libellé réel,
  suivi du mode, édition inchangée, case vidée, remplacement du libellé).
- `scripts/test-mutations-colonnes.sh` : **10 contrôles** — les mutations 8 et 9
  remettent la case vide et la création de règles inutiles, et sont détectées.

## 2026-10-28 — Le menu « Libellés des colonnes » est désormais visible

### Fixed

- **Menu introuvable** : l'entrée était ajoutée dans `setupMenu`, donc **avant**
  l'ouverture de la session. La vérification des droits répondait alors
  « utilisateur de la session inconnu », ce qui était interprété comme un refus :
  le menu disparaissait pour **tout le monde**, y compris pour l'administrateur.
  Le menu est maintenant ajouté au démarrage (`start()`), dans la barre de menus
  du client, **menu `Paramètres` juste avant `Aide`** (repli dans `Structure` si
  cette version de client refuse la création du menu).
- Tant que l'utilisateur courant n'est pas connu, le module **réessaie toutes
  les 2 s pendant 30 s** au lieu de renoncer (`ColumnLabelRules.accessIsUndetermined`) ;
  seul un refus explicite (« le rôle le plus haut est X ») masque le menu.
- Le libellé exact du chemin est corrigé dans toute la documentation :
  **Paramètres → Libellés des colonnes** (`Affichage` est un groupe de séparation
  interne, pas un sous-menu).

### Tests

- `ColumnLabelRulesTest` : 40 tests (nouveau test sur la décision « indéterminée »).
- `scripts/test-mutations-colonnes.sh` : 8 contrôles — la mutation 7 traite à
  nouveau un utilisateur inconnu comme un refus et la suite **échoue**, donc le
  comportement est bien protégé.

## 2026-10-28 — Correctif : le module ne démarrait plus (« Already added ID_AFFAIRE »)

### Fixed

- **Crash au démarrage du module** : `ID_AFFAIRE` était déclaré **deux fois** sur
  `FACTURE_FOURNISSEUR` (`SupplierInvoiceAffairComponentSupport` puis la boucle
  sur `DIRECT_AFFAIR_TABLES`), et `ComponentsContext.putAdditionalField` lève
  `IllegalStateException` sur un doublon. Résultat :
  `Unable to start JarModuleFactory org.openconcerto.modules.project (1.1)` et
  plus aucun service du module (historique des affaires, menus, rattachement).
- Un seul point d'entrée, `AffairLinkSupport.registerComponentFields` : une
  déclaration par table, « déjà déclaré » traité comme une information, toute
  autre erreur collectée sans interrompre le démarrage ; compte rendu tracé.
- Tests de non-régression : le double de `ComponentsContext` lève désormais comme
  le vrai, deux tests rejouent le scénario du plantage, et les mutations 10 et 11
  de `scripts/test-mutations-affaire.sh` prouvent que la suite sait échouer sur
  ce point.
- Documentation : `docs/correctif-demarrage-already-added.md` (cause, correctif,
  vérifications, quoi faire sur un poste planté) et `docs/construire-le-jar.md`
  (cloner, construire, tester, publier).

## 2026-10-28 — Paramètres : libellés des colonnes pour toute l'équipe

### Added

- **Menu « Paramètres → Libellés des colonnes »**, visible uniquement
  pour l'utilisateur qui a **le plus de droits dans la base** (super-utilisateurs,
  sinon administrateurs, sinon le plus grand nombre de droits dans `USER_RIGHT` ;
  comptes désactivés ignorés). Il y choisit, pour toute l'équipe, le nom affiché
  des colonnes des listes : plus de `ID_CLIENT`, `ID_AFFAIRE`,
  `ID_FACTURE_FOURNISSEUR` mais `CLIENT`, `AFFAIRE`, `FACTURE FOURNISSEUR`.
- **Deux emplacements de stockage** : la table `PROJECT_COLUMN_LABEL` du
  **serveur SQL** (source de vérité, partagée par tous les postes, avec
  `TABLE_NAME`, `COLUMN_NAME`, `LABEL`, `DATE`, `ID_USER` et un index unique) et
  le fichier `column-labels.properties` **embarqué dans le jar** (valeurs par
  défaut d'une nouvelle installation, exportables depuis l'écran).
- Trois modes : `AUTO` (défaut : suppression du préfixe `ID_`), `MAPPING`
  (uniquement les règles saisies), `OFF` (aucun changement, retour arrière
  immédiat), enregistrés dans `PROJECT_SETTINGS`.
- Règles par table (`COMMANDE.ID_AFFAIRE`) ou pour toutes les tables
  (`*.ID_CLIENT`), appliquées sans modifier le cœur OpenConcerto : modèle des
  listes du module + en-têtes de tous les tableaux de l'application.
- `ColumnLabelRules` (règles pures, SQL inclus), `ColumnLabelStore` (lecture /
  écriture, valeurs du jar), `ColumnLabelAccess` (choix du rôle le plus haut),
  `ColumnLabelUi` (application à l'interface), `ColumnLabelSettingsAction`
  (écran de paramétrage).
- `tests/sql/migration-colonnes.sql`, `tests/sql/fixture-colonnes.sql`,
  `tests/sql/e2e-colonnes.sh` (34 contrôles),
  `tests/org/.../ColumnLabelRulesTest.java` (39 tests),
  `scripts/test-mutations-colonnes.sh` (7 mutations),
  `docs/parametres-colonnes.md`.

### Validation

- `sh scripts/run-tests.sh` : 35 + 39 + 16 tests OK.
- `sh tests/sql/e2e-colonnes.sh` : 34 contrôles, 0 échec.
- `sh scripts/test-mutations-colonnes.sh` : 7 contrôles, 0 échec.

## 2026-10-26 — Affaire sur les documents fournisseurs : audit et correctif

### Fixed

- **Facture fournisseur absente de la liste des tables à affaire**
  (`Module.listTableAffaire`) : elle n'avait donc ni colonne « Affaire » dans la
  liste de l'ERP, ni action « Historique affaire », et sa colonne n'était jamais
  créée lors de l'installation. La liste du module vient maintenant de
  `AffairLinkSupport.DIRECT_AFFAIR_TABLES`, qui la contient.
- **Colonnes `ID_AFFAIRE` réparées à chaque démarrage**
  (`Module.ensureAffairColumns`) : jusqu'ici elles n'étaient créées qu'à la
  première installation du module, puis pour quatre tables seulement
  (`COMMANDE`, `SAISIE_ACHAT`, `AVOIR_FOURNISSEUR`… pouvaient rester sans
  colonne, donc sans affaire enregistrable).
- **Création de colonne non bloquée par les affaires supprimées** : la colonne
  est ajoutée seule, puis la contrainte `FOREIGN KEY … NOT VALID`. Un document
  pointant vers une affaire inexistante ne peut plus empêcher la création de la
  colonne (l'ancien `ADD COLUMN … REFERENCES` échouait entièrement et l'erreur
  n'était qu'imprimée dans la console).
- **Historique des affaires : plus de boucle de filtrage cassée**
  (`ProjectHistory.putAffairTab`). Un onglet dont la table n'a pas `ID_AFFAIRE`
  et aucun parent rattachable est ignoré avec un message, au lieu de faire lever
  une exception à `ListeHistoriquePanel` — exception qui laissait **tous les
  onglets suivants** non filtrés (donc invisibles).
- **Lignes des commandes/bons de réception rattachées par leur document** : le
  filtrage passe par le document parent même quand la table de lignes porte sa
  propre colonne `ID_AFFAIRE`, sinon les lignes dont l'affaire de ligne est vide
  (le cas normal) disparaissaient de l'historique.
- Action « Modifier » disponible sur les factures fournisseurs et les achats
  depuis l'historique des affaires.

### Added

- `AffairLinkSupport` : règles pures et testables du rattachement à une affaire
  (tables concernées, plan de filtrage d'un onglet, colonnes manquantes, champs
  à exposer dans les écrans).
- `AffairLinkSupportTest` : 35 tests.
- `tests/sql/e2e-affaire-fournisseur.sh` : 26 contrôles de bout en bout sur
  PostgreSQL (pglite), avec la base « installation existante » et la migration.
- `tests/sql/migration-affaire-fournisseur.sql` : DDL de référence, idempotent,
  index inclus, contraintes `NOT VALID`.
- `scripts/diagnostic-affaire-fournisseur.sh` : diagnostic **lecture seule** de
  la base du client (colonnes manquantes, lignes sans affaire, lignes cachées,
  affaires inexistantes, mode démonstration `--pglite`).
- `tests/sql/scenario-creation-fournisseur.sh` : **scénario complet de 71
  contrôles** — création d'une affaire, saisie d'une commande fournisseur
  rattachée (en-tête + lignes), transfert en facture fournisseur rattachée,
  modification de l'affaire d'un document déjà enregistré (changement d'affaire,
  retrait), garde-fous (affaire « Indéfinie », affaire inexistante, affaire
  supprimée), puis **une requête par onglet de l'historique**, dans l'ordre de
  `ProjectHistory` : c'est la reproduction de la boucle de
  `ListeHistoriquePanel` qui cassait.
- `scripts/test-affaire-fournisseur.sh` : suite complète en une commande
  (Java + e2e + scénario + mutations), avec `--sans-java` et
  `--sans-mutations`.
- `scripts/test-mutations-affaire.sh` : 10 tests de mutation (ajout de
  « scénario sans migration » et « base client sans colonne sur les factures
  fournisseurs »).
- `docs/audit-affaire-fournisseur.md` : rapport d'audit complet.

### Release

- Jar `org.openconcerto.modules.project-1.1.jar` (version déclarée inchangée :
  `1.1`), compilé et publié par `.github/workflows/release.yml` contre
  OpenConcerto 1.7.6 officiel, contrôle du bytecode Java 8, empreinte SHA-256
  publiée avec le jar. Notes : `docs/release-1.1-affaire-fournisseur.md`.
- Recette graphique clic par clic : `docs/recette-graphique-affaire-fournisseur.md`.
- `scripts/installer-jar-release.sh` : pose le jar dans le ou les dossiers
  `Modules` du client (détection `Modules` relatif au lancement, contrôle du
  module et de sa version, bytecode Java 8, sauvegarde de l'ancien jar, nom
  conventionnel `<id>-<version>.jar`, `--dry-run`, `--liste`).
- `tests/installer/test-installer-jar.sh` : 19 contrôles du script
  d'installation (détection, refus d'un fichier qui n'est pas un module, refus
  d'un autre module, `--dry-run` sans écriture, un seul jar actif à la fin,
  aucun accès SQL).
- `docs/installation-du-jar.md` : où mettre le jar (Windows, Linux, macOS),
  comment trouver le bon dossier, `NO_FACTORY`, retour arrière.
- Correction de compilation : `ComponentsContext` n'expose pas sa base
  (`ElementContext.getRoot()` est protégé) → `Module.affairRoot(ComponentsContext)`
  passe par l'élément `AFFAIRE`.

### Validation

- `sh scripts/run-tests.sh` : 35 + 16 tests OK.
- `sh tests/sql/e2e-affaire-fournisseur.sh` : 26 contrôles, 0 échec.
- `sh tests/sql/scenario-creation-fournisseur.sh` : 71 contrôles, 0 échec.
- `sh scripts/test-mutations-affaire.sh` : 10 contrôles, 0 échec.
- `sh scripts/test-affaire-fournisseur.sh` : 4 suites, 0 échec.
- Compilation de vérification Java 8 (ECJ `-source 1.8 -target 1.8`).

## 2026-10-24 — Affaire reprise lors du transfert commande fournisseur → facture

### Added

- Le transfert **Commandes fournisseurs → Factures fournisseurs** recopie
  maintenant `COMMANDE.ID_AFFAIRE` dans `FACTURE_FOURNISSEUR.ID_AFFAIRE` tout en
  conservant l’injecteur natif OpenConcerto pour les autres champs et les lignes.
  Les lignes de facture dont `ID_AFFAIRE` est vide ou indéfini reprennent aussi
  l’affaire de leur commande ; une affaire de ligne déjà définie est conservée.
- L’en-tête de l’écran de facture fournisseur expose maintenant le champ
  **Affaire**, afin de voir la valeur reprise avant l’enregistrement.
- `SupplierOrderToInvoiceSQLInjectorTest` : 16 tests de contrat couvrant la
  copie de l’affaire dans l’en-tête et les lignes, la préservation des affaires
  de ligne définies, l’enregistrement de l’injecteur et du champ d’en-tête, les
  valeurs vides et indéfinies, les transferts successifs et groupés, ainsi que
  les schémas sans colonne `ID_AFFAIRE`.
- Procédure de recette graphique :
  `docs/test-transfert-commande-fournisseur-facture.md`.

### Compatibility

- `module.properties` reste volontairement en `version=1.1` pour correspondre à
  la version du module enregistrée dans la base installée. Ce correctif ne
  demande aucune migration de version de la DB et produit
  `org.openconcerto.modules.project-1.1.jar`.

### Validation

- `AffairListSortSupportTest` : OK.
- `SupplierOrderToInvoiceSQLInjectorTest` : 16 tests OK.

## Module project 1.5 - 2026-10-22 (à publier)

### Added

- `scripts/fix-module-version.sh` : diagnostic et correction de la version du
  module épinglée en base. Quand le jar est remplacé, la base garde l'ancienne
  version (`FWK_MODULE_METADATA` + préférence `modules/required`) et le client
  refuse de démarrer avec `NO_FACTORY=[Module … v1.1]`. Le script aligne la
  base sur la version du jar (transaction SQL, idempotente, lecture seule par
  défaut).

- `scripts/build-release.sh` : préparation d'une release (bump de version,
  compilation Java 8, jar dans `dist/`, tag Git, push) et publication d'une
  **release GitHub avec le jar compilé en pièce jointe**.
- `docs/release-process.md` : pourquoi OpenConcerto inscrit les modules dans
  `FWK_MODULE_METADATA`, comment le numéro de version est utilisé au
  démarrage, et la procédure de publication pas à pas.

### Fixed

- `FWK_MODULE_METADATA` : le numéro de version enregistré pour les colonnes
  `ID_AFFAIRE` créées par le module suit maintenant la version déclarée du
  module (il était codé en dur à `1.0` alors que le module est en `1.2`).

### Changed

- Le transfert « demande de prix » → « commande fournisseur » reprend les
  prix de la demande de prix comme **valeurs de départ** (convention du core
  OpenConcerto) au lieu de les vider : `T_PA_HT` est `NOT NULL` dans
  `COMMANDE_ELEMENT`. Les totaux sont recalculés par le client.

## 2026-10-22 — Transfert « demande de prix » → « commande fournisseur »

### Added

- Bouton « Transfert en commande fournisseur » dans l'onglet « Demandes de
  prix » de l'historique des affaires (sélection d'une seule demande).
- Transfert complet : en-tête (fournisseur, date, affaire) et lignes
  (désignation, quantité, article, unité) recopiés vers une nouvelle commande
  fournisseur.
- Table de transfert `TR_DEMANDE_PRIX` créée **automatiquement** par le core
  OpenConcerto (rien à faire en SQL, rien à créer à la main).
- Documentation : `docs/transfert-demande-prix-commande.md`,
  `docs/test-transfert-demande-prix-interface-graphique.md`,
  `docs/message-pere-demande-prix-commande.md`.

### Validation

- Bouton visible dans le client 1.7.6 (« Gestion Projet v1.2 — Démarré »).
- `scripts/structure-demande-prix.sh --mode docker` : `TR_DEMANDE_PRIX`
  présente, avec `ID_DEMANDE_PRIX` → `DEMANDE_PRIX` et `ID_COMMANDE` →
  `COMMANDE`.
- `scripts/panel-tests-docker.sh --stack ~/oc-176-docker` : aucun échec.

## 2026-10-10 — N° commande fournisseur dans l'historique des factures

### Added

- A `N° commande fournisseur` column in the `Factures fournisseurs` tab of the affair history window, so each supplier invoice can be matched with the supplier order it comes from (same `NUMERO` as displayed in the `Commandes fournisseurs` tab).

### Behavior

- The order number is resolved first through the OpenConcerto transfer table `TR_COMMANDE` (filled by the order-to-invoice transfer), then through the invoice lines (`FACTURE_FOURNISSEUR_ELEMENT.ID_COMMANDE_ELEMENT` -> `COMMANDE_ELEMENT.ID_COMMANDE`) as a fallback.
- Invoices built from several orders show all order numbers, separated by commas.
- Invoices entered manually (no linked order) show an empty cell.
- The column is inserted right after the invoice number column and degrades gracefully when the optional tables or fields are missing.

### Validation

- `AffairListSortSupportTest` passes.
- The new history column code compiles with `javac` targeting Java 8.

## 2026-08-05 — Tri du sélecteur d'affaires

### Added

- Automated tests for the affair history selector sort behavior.
- A lightweight `scripts/run-tests.sh` test runner for the extracted sort logic.

### Changed

- Extracted affair-list sort rules into a small testable support class.
- Centralized the default sort constants so the visible combo selection and the initially applied comparator stay aligned.

### Validation

- `sh scripts/run-tests.sh`
- `./scripts/build-java8-compatible.sh`
- Java bytecode verification: all classes are classfile major version `52` or lower.

## 2026-07-30 — Tri par défaut et documentation de release

### Added

- Professional release documentation for the default affair-name sort feature.

### Changed

- The history screen's affair selector now defaults to `Tri par nom`.
- The initial comparator installed on the affair selector now matches the visible default selection.
- The build script now derives the JAR version from `module.properties`, reducing release-version drift.

### Preserved

- Users can still switch manually to `Tri par date`.
- Closed affairs remain hidden by default through `Masquer dossiers clos`.
- Date rendering in the affair selector remains unchanged when affair dates are available.

### Validation

- `./scripts/build-java8-compatible.sh`
- Java bytecode verification: all classes are classfile major version `52` or lower.

## 2026-07-08 — Historique des affaires

### Changed

- Integrated the previous runtime patch behavior directly into source-controlled Java code.
- Added affair history sorting controls, closed-affair filtering, direct affair modification, optional-table tolerance, family filters, supplier display corrections, and Java 8 compatible packaging.
