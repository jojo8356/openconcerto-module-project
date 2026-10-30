# OpenConcerto Project Module

Personal OpenConcerto module for project/affair management.

## Current Release

- Module id: `org.openconcerto.modules.project`
- Version: `1.1`
- Release date: `2026-08-05`
- Main change: the affair history selector default sort is now covered by automated tests.

The module has been compiled and installed locally as:

```text
/home/jojokes/.local/share/OpenConcerto/Modules/org.openconcerto.modules.project-1.1.jar
```

## Java Compatibility

The module is built for Java 8 bytecode so the same JAR can run on Java 8 through Java 21, provided the host OpenConcerto runtime is compatible.

Build the module with:

```sh
./scripts/build-java8-compatible.sh
```

The script uses `javac --release 8` on JDK 9+ and falls back to `-source 8 -target 8` on JDK 8. It then verifies that every compiled class in the JAR has classfile major version `52` or lower.

If OpenConcerto is not installed at `/opt/openconcerto/OpenConcerto.jar`, pass its path explicitly:

```sh
OPENCONCERTO_JAR=/path/to/OpenConcerto.jar ./scripts/build-java8-compatible.sh
```

## Notes

- Source code is under `src/org/openconcerto/modules/project`.
- Module metadata is in `module.properties`.
- The affair history list supports both `Tri par nom` and `Tri par date`; `Tri par nom` is the tested default release behavior.
- `DATE` remains available for date sorting and list display.
- Runtime bytecode/JAR patch classes have been removed.

## Affaire sur les commandes et factures fournisseurs

Le rattachement a une affaire des documents fournisseurs est verifie par quatre
suites executables, lancables d'une seule commande :

```sh
sh scripts/test-affaire-fournisseur.sh      # tout : Java + SQL + scenario + mutations
```

ou separement :

```sh
sh scripts/run-tests.sh                                  # tests Java (regles + transfert)
sh tests/sql/e2e-affaire-fournisseur.sh                  # 26 controles SQL (base existante + migration)
sh tests/sql/scenario-creation-fournisseur.sh            # 71 controles : creer une affaire, une commande
                                                         # fournisseur puis sa facture, modifier leur affaire
sh scripts/test-mutations-affaire.sh                     # verifie que tout cela sait echouer
```

Le scenario de creation rejoue exactement le parcours utilisateur : affaire,
commande fournisseur rattachee (en-tete + lignes), transfert en facture
fournisseur rattachee, puis modification de l'affaire d'un document deja
enregistre. Il interroge ensuite **chaque onglet** de l'historique des affaires,
dans l'ordre du module. `SANS_MIGRATION=1` rejoue le scenario sur une base
d'avant correctif : il doit alors echouer (c'est la mutation 8).

Pour diagnostiquer une base client (lecture seule) :

```sh
sh scripts/diagnostic-affaire-fournisseur.sh --host 127.0.0.1 --port 5433 \
   --db OpenConcerto --user openconcerto --schema OpenConcerto42 --affaire 330
```

Analyse complete : `docs/audit-affaire-fournisseur.md`.

## Release du jar (version 1.1)

Le jar du module est compile et publie par le workflow
`.github/workflows/release.yml` (OpenConcerto 1.7.6 officiel, bytecode Java 8) :

```sh
# publication automatique : pousser un tag v1.1*
git tag v1.1-affaire-fournisseur && git push origin v1.1-affaire-fournisseur
```

La release contient `org.openconcerto.modules.project-1.1.jar`, son empreinte
SHA-256 et les notes de version (`docs/release-1.1-affaire-fournisseur.md`).

### Où mettre le jar apres telechargement

Dans le dossier **`Modules` du client OpenConcerto** (le jar directement dedans,
et un seul jar par module). Le chemin exact se lit dans le client :
menu **? / Aide -> Informations**, ligne « Dossiers des modules ».

```sh
sh scripts/installer-jar-release.sh --liste        # quels dossiers Modules ?
sh scripts/installer-jar-release.sh --jar ~/Downloads/org.openconcerto.modules.project-1.1.jar
```

Detecte les dossiers, controle le module et sa version, sauvegarde l'ancien jar
dans `Modules/_backup_modules/`, copie le nouveau sous son nom conventionnel.
Guide complet (Windows, Linux, macOS, cas `NO_FACTORY`, retour arriere) :
`docs/installation-du-jar.md`. Recette graphique :
`docs/recette-graphique-affaire-fournisseur.md`.

## Construire le jar

```sh
git clone https://github.com/jojo8356/openconcerto-module-project.git
cd openconcerto-module-project
sh scripts/build-jar-with-curl.sh   # telecharge OpenConcerto 1.7.6 (une fois) et compile
# -> build/org.openconcerto.modules.project-1.1.jar
```

Prérequis : un **JDK** 8+ (17 recommandé), `curl`, `unzip` ; `node` pour les tests
SQL. Détails et variantes (jar OpenConcerto déjà présent, publication d'une
release) : `docs/construire-le-jar.md`.

## Paramètres : libellés des colonnes

Le menu **Paramètres → Libellés des colonnes** (visible seulement pour
l'utilisateur qui a le plus de droits dans la base) permet de choisir, pour toute
l'équipe, le nom affiché des colonnes des listes : `ID_CLIENT` devient `CLIENT`,
`ID_FACTURE_FOURNISSEUR` devient `FACTURE FOURNISSEUR`.

Les réglages sont stockés **sur le serveur SQL** (tables `PROJECT_COLUMN_LABEL` et
`PROJECT_SETTINGS`, donc partagés par tous les postes) et, pour les valeurs par
défaut, **dans le jar** (`column-labels.properties`).

```sh
sh tests/sql/e2e-colonnes.sh           # 34 controles SQL (pglite)
sh scripts/test-mutations-colonnes.sh  # verifie que ces tests savent echouer
```

Documentation : `docs/parametres-colonnes.md`.

## Documentation

- Release notes: `CHANGELOG.md`
- Technical release file: `docs/patch-integration-revision-report.md`
- Architecture and module inventory: `docs/index.md`
