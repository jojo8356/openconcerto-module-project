# Tests des panneaux du module `org.openconcerto.modules.project` (v1.1)

Suite de tests Java qui verifie, **sur tous les panneaux** du module, que les
donnees affichees par l'application sont bien **TOUTES** les donnees de la
base, et qu'**aucune ligne n'est cachee**.

Les tests sont **en lecture seule** : aucune ecriture n'est faite dans la
base.

## 1. Ce qui est verifie

Quatre controles, tous joues sur les schemas qui contiennent une table
`AFFAIRE` (en general `Default` et `OpenConcerto42`) :

| Controle | Question posee | Code en cas de probleme |
|---|---|---|
| `StructureSuite` | Les tables et les colonnes lues par chaque panneau existent-elles ? | `ECHEC` |
| `VisibilitySuite` | Toutes les lignes de la table sont-elles affichees par le panneau ? Aucune ligne n'est-elle invisible (affaire inexistante, mere disparue, filtre) ? | `ECHEC` / `ALERTE` |
| `AggregateSuite` | Les totaux affiches (bilan) sont-ils egaux aux totaux reels des tables ? Le recensement des lignes est-il complet ? | `ALERTE` / `ECHEC` |
| `RightsSuite` | Un utilisateur a-t-il un refus explicite de lecture sur une table affichee par un panneau ? | `ECHEC` |

### Exemples de problemes detectes

* `FACTURE_FOURNISSEUR_ELEMENT.ID_COMMANDE_ELEMENT` absente (colonne, cle
  etrangere ou index) : c'est le bug de production rencontre sur le transfert
  « commande fournisseur -> facture fournisseur » ;
* une ligne rattachee a une `AFFAIRE` qui n'existe plus : elle n'apparait dans
  aucun panneau ;
* une ligne dont la table mere a disparu (`COMMANDE_ELEMENT` sans
  `COMMANDE`, `BON_RECEPTION_ELEMENT` sans `BON_RECEPTION`) ;
* une ligne sans `ID_AFFAIRE` : invisible dans l'historique et dans le bilan ;
* un ecart entre un total affiche et le total reel de la table ;
* un droit `SELECT_ROW` refuse explicitement sur une table de panneau.

## 2. Modele de donnees utilise

* une ligne porte `ID_AFFAIRE` (directement, ou via sa table mere) ;
* **les cles primaires sont lues dans le catalogue PostgreSQL**
  (`pg_index` / `pg_class` / `pg_attribute`) et mises en cache : toutes les
  tables n'ont pas une colonne « ID » (par exemple `DEVIS`, dont la cle
  primaire s'appelle `ID_DEVIS`) ;
* l'affaire `ID = 1` est la ligne technique « Indefini » : elle n'est jamais
  affichee dans l'historique ;
* l'historique (`ProjectHistory`) affiche les lignes rattachees a l'affaire
  selectionnee, dossier clos (`ID_ETAT_AFFAIRE = 6`) masque par defaut ;
* l'onglet « Commandes en cours » filtre sur `ID_ETAT_AFFAIRE = 3`, l'onglet
  « Devis en attente » sur `ID_ETAT_DEVIS = 2` ;
* les totaux du bilan sont recalcules depuis la base et compares aux formules
  de `HistoriqueAffaireBilanPanel`.

## 3. Panneaux couverts

* **Listes** : affaires, devis, commandes clients, demandes de prix, demandes
  d'achat, factures clients, avoirs clients, bons de livraison, commandes
  fournisseurs, achats, avoirs fournisseurs ;
* **Historique** (20 onglets) : affaires, devis, commandes clients,
  chiffrage, factures, avoirs, demandes d'achat, demandes de prix, bons de
  livraison, commandes fournisseurs, articles commandes, bons de reception,
  articles receptionnes, achats, factures fournisseurs, elements de facture
  fournisseur, avoirs fournisseurs, temps, stock, note de frais, pointage ;
* **Onglets du module** : « Affaires », « Commandes en cours », « Devis en
  attente » ;
* **Bilan** : marche, budget chiffre, montant facture, avoirs clients, achats,
  factures fournisseurs, articles de facture fournisseur, avoirs
  fournisseurs, commandes fournisseurs, articles commandes ;
* **Export** : `ProjectImportExport` ;
* **Contrat de structure** : colonnes `ID_AFFAIRE` ajoutees par le module,
  colonne `ID_COMMANDE_ELEMENT` des factures fournisseurs et des bons de
  reception.

## 4. Comment lancer les tests

### 4.1 Dans la VM (la ou PostgreSQL et `psql` sont installes)

Tout se lance **depuis le poste**, en SSH : la VM doit simplement etre
demarree, et sa stack PostgreSQL en route.

```bash
# 1. la VM (console dans ce terminal : Ctrl-A puis X pour l'arreter)
bash scripts/create-debian-vm.sh status
bash scripts/create-debian-vm.sh start

# 2. la stack PostgreSQL de la VM (seulement apres un redemarrage de la VM)
ssh -p 2222 oc@127.0.0.1 "cd ~/oc-176/docker/openconcerto-1.7.6 && \
  sudo docker compose -f docker-compose.yml -f docker-compose.fr_FR.yml up -d"

# 3. la suite de tests
bash scripts/panel-tests-in-vm.sh
```

Le script `panel-tests-in-vm.sh` :

* verifie l'acces SSH (port 2222, compte `oc`, cle `~/.ssh/id_ed25519_oc176`
  si elle existe) ;
* installe un JDK headless dans la VM si besoin (une seule fois) ;
* telecharge les 14 fichiers de test et le lanceur depuis GitHub
  (branche `arena/61954a71-openconcerto-module-project`, donc la derniere
  version) ;
* compile et execute la suite contre `127.0.0.1:5433`, base `OpenConcerto`
  (le mot de passe est lu dans le `.env` de la stack de la VM).

Lecture seule : aucune ecriture n'est faite dans la base.

Options : `--host`, `--port` (port SSH, defaut 2222), `--user` (defaut `oc`),
`--db`, `--schemas`, `--ref` (branche GitHub).

Pour lancer la suite a la main dans la VM (une fois les sources telechargees
par le script ci-dessus) :

```bash
ssh -p 2222 oc@127.0.0.1
cd ~/oc-176
sh scripts/run-panel-tests.sh --host 127.0.0.1 --port 5433 --db OpenConcerto \
   --user openconcerto \
   --password "$(sed -n 's/^POSTGRES_PASSWORD=//p' docker/openconcerto-1.7.6/.env)"
```

La base de la VM est la copie verifiee de la production : le verdict doit
etre identique a celui du poste, avec en plus le schema `Default` (les deux
schemas ont recu le correctif `ID_COMMANDE_ELEMENT`).

### 4.2 Sur le poste, a travers le tunnel SSH

```bash
git clone https://github.com/jojo8356/openconcerto-module-project.git
cd openconcerto-module-project
sh scripts/run-panel-tests.sh --host 127.0.0.1 --port 5434 --db OpenConcerto --user openconcerto
```

Il faut un JDK 8+ (`javac`) sur le poste, et `psql` (ou un pilote JDBC
`postgresql-*.jar` dans le classpath) :

```bash
# avec le pilote JDBC :
sh scripts/run-panel-tests.sh --jdbc /usr/share/java/postgresql.jar --host 127.0.0.1 --port 5434 --db OpenConcerto --user openconcerto
```

Le mot de passe peut venir de l'environnement (evite de le laisser dans
l'historique du shell) :

```bash
PGPASSWORD='...' sh scripts/run-panel-tests.sh --host 127.0.0.1 --port 5434 --db OpenConcerto --user openconcerto
```

### 4.3 Contre la base Docker/Podman du poste (sans passer par la VM)

Quand la base est dans la stack Podman du poste (`~/oc-176-podman`, port
publie `127.0.0.1:5433`) :

```bash
bash scripts/panel-tests-docker.sh
```

Le runtime est detecte automatiquement (podman s'il est present, sinon
docker ; les deux ne sont jamais melanges). Le script lit la configuration de
la stack dans son `.env` (role, mot de passe, base, port) et, a defaut,
deduit le mot de passe et les noms de l'environnement du conteneur
PostgreSQL lui-meme ; il demarre la stack si elle est arretee, attend
PostgreSQL, puis compile et execute la suite :

* si le poste a un JDK (`javac`), tout tourne en local, avec le pilote JDBC
  trouve automatiquement (y compris un JAR du client OpenConcerto qui
  contient `org/postgresql/Driver.class`) ou `psql` ;
* sinon, la compilation **et** l'execution se font dans un conteneur
  `docker.io/library/eclipse-temurin:17-jdk` qui partage l'espace de reseau du
  conteneur PostgreSQL (connexion sur `127.0.0.1:5432` de l'interieur).

Options utiles : `--stack`, `--port`, `--db`, `--user`, `--password`,
`--schemas`, `--mode local|container`, `--jdk IMAGE`, `--jdbc JAR`,
`--no-start`.

### 4.4 Sans PostgreSQL : test de bout en bout avec pglite

```bash
npm install
sh tests/sql/e2e-panneaux.sh
```

Le scenario joue une base contenant des anomalies volontaires (la suite doit
les detecter) puis la meme base « propre » (la suite doit passer).

## 5. Lire les resultats

```
OK     [schema / panneau] controle
ALERTE [schema / panneau] donnee non attachee a une affaire (invisible dans l'historique)
ECHEC  [schema / panneau] donnee cachee, colonne manquante, droit refuse, ...
```

Compte en fin de rapport :

```
Controles : 112 au total | 82 OK | 13 info | 11 alertes | 6 echecs
RESULTAT : ECHEC (6 controle(s) en echec)
```

* code de sortie **0** : aucun probleme ;
* code de sortie **1** : au moins un controle en echec ;
* code de sortie **2** : erreur d'execution (connexion impossible, base
  introuvable...).

## 6. Fichiers

| Fichier | Role |
|---|---|
| `tests/org/openconcerto/modules/project/panels/TestRunner.java` | point d'entree, options, code de sortie |
| `tests/org/openconcerto/modules/project/panels/Catalogue.java` | description de tous les panneaux du module |
| `tests/org/openconcerto/modules/project/panels/PanelSql.java` | construction du SQL des panneaux (jointures, filtres) |
| `tests/org/openconcerto/modules/project/panels/StructureSuite.java` | controle 1 : tables et colonnes |
| `tests/org/openconcerto/modules/project/panels/VisibilitySuite.java` | controle 2 : aucune donnee cachee |
| `tests/org/openconcerto/modules/project/panels/AggregateSuite.java` | controle 3 : totaux et recensement |
| `tests/org/openconcerto/modules/project/panels/RightsSuite.java` | controle 4 : droits utilisateurs |
| `tests/org/openconcerto/modules/project/panels/JdbcSqlClient.java` | transport JDBC (si le pilote est present) |
| `tests/org/openconcerto/modules/project/panels/PsqlSqlClient.java` | transport `psql` (mode CSV) |
| `scripts/run-panel-tests.sh` | compilation + execution |
| `scripts/panel-tests-in-vm.sh` | execution dans la VM |
| `scripts/panel-tests-docker.sh` | execution contre la base Docker/Podman du poste |
| `tests/sql/fixture-panneaux.sql` | base de test avec anomalies volontaires |
| `tests/sql/fixture-panneaux-nettoye.sql` | la meme base, sans anomalie |
| `tests/sql/e2e-panneaux.sh` | test de bout en bout (pglite) |
