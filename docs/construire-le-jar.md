# Cloner et construire le jar (poste de développement)

Ce guide décrit la construction **locale** du jar du module, avec le vrai
`OpenConcerto.jar` (l'API du cœur est nécessaire à la compilation), et les
vérifications à lancer avant de livrer.

## 1. Prérequis

| Outil | Version | À quoi ça sert |
|---|---|---|
| `git` | récente | cloner le dépôt |
| Un **JDK** | 8 à 21 (17 recommandé) | compiler en bytecode Java 8 (`--release 8`) |
| `curl` | récente | télécharger l'archive OpenConcerto (une seule fois) |
| `unzip` | récente | extraire `OpenConcerto.jar` de l'archive |
| `node` (optionnel) | 18+ | tests SQL `tests/sql/*.sh` (pglite) |

Windows : utiliser **WSL** ou **Git Bash** (les scripts sont en `sh`).

## 2. Cloner

```sh
git clone https://github.com/jojo8356/openconcerto-module-project.git
cd openconcerto-module-project

# la branche de travail en cours (contient le dernier lot)
git checkout arena/ff79607f-openconcerto-module-project
git log --oneline -5
```

`main` contient l'état fusionné ; la branche `arena/…` contient les lots en
cours de revue. Le numéro de version est dans `module.properties` (`version=1.1`)
et **ne doit pas être modifié sans raison** : le nom du jar en dépend.

## 3. Construire le jar

```sh
sh scripts/build-jar-with-curl.sh
```

Ce que fait le script, dans l'ordre :

1. réutilise `$OPENCONCERTO_JAR` s'il est défini ;
2. sinon `/opt/openconcerto/OpenConcerto.jar` s'il existe ;
3. sinon télécharge `OpenConcerto-1.7.6-multiposte.zip` (~90 Mo) dans
   `build/openconcerto-dist/` et l'extrait (le téléchargement n'est fait qu'une
   fois, le dossier est ignoré par Git) ;
4. compile **tout** `src/**/*.java` en bytecode Java 8 contre `OpenConcerto.jar` ;
5. copie les ressources (`.properties`, `.xml`, images) dans le jar ;
6. vérifie le bytecode Java 8 et écrit
   `build/org.openconcerto.modules.project-1.1.jar`.

Sortie attendue (la dernière ligne) :

```
build/org.openconcerto.modules.project-1.1.jar
```

### Variantes utiles

```sh
# j'ai déjà un OpenConcerto.jar (poste client, pas d'internet) :
OPENCONCERTO_JAR=~/openconcerto/OpenConcerto.jar sh scripts/build-jar-with-curl.sh

# je veux seulement télécharger l'archive, sans compiler :
SKIP_BUILD=1 sh scripts/build-jar-with-curl.sh

# je veux seulement compiler, avec mes options :
OPENCONCERTO_JAR=... sh scripts/build-java8-compatible.sh
```

Vérifier le contenu du jar produit :

```sh
unzip -l build/org.openconcerto.modules.project-1.1.jar | grep -E "Module.class|AffairLinkSupport.class|ColumnLabel.*\.class|column-labels.properties"
unzip -p build/org.openconcerto.modules.project-1.1.jar META-INF/openConcertoModule.properties
sha256sum build/org.openconcerto.modules.project-1.1.jar
```

## 4. Lancer les tests

```sh
sh scripts/run-tests.sh                 # Java : affaire, libellés, transferts (sans base)
sh tests/sql/e2e-colonnes.sh            # SQL : tables des libellés (pglite)
sh tests/sql/e2e-affaire-fournisseur.sh # SQL : colonnes d'affaire
sh tests/sql/scenario-creation-fournisseur.sh  # scénario commande -> facture fournisseur
sh scripts/test-affaire-fournisseur.sh  # tout, y compris les mutations
```

Les trois premiers n'ont besoin de rien d'autre que le JDK ; les suivants
installent `@electric-sql/pglite` via `npm` au premier lancement (donc il faut
`node` et un accès réseau).

> Au premier lancement, `e2e-*.sh` écrit dans `node_modules/` et dans un
> répertoire temporaire (`WORK_DIR=/tmp/…`) : rien n'est ajouté au dépôt.

## 5. Essayer le jar dans le client

```sh
# ferme OpenConcerto, puis :
sh scripts/installer-jar-release.sh --jar build/org.openconcerto.modules.project-1.1.jar
```

Le script montre le dossier `Modules` détecté, déplace l'ancien jar (jamais deux
jars du même module), installe le nouveau et vérifie la version. Sans le script :
copier le jar dans le dossier **Modules** (chemin fiable : client → **? / Aide →
Informations → « Dossiers des modules »**) et redémarrer le client.

## 6. Publier une release (CI)

Le jar livrable est construit par GitHub Actions avec le vrai `OpenConcerto.jar`
1.7.6, puis attaché à une release :

```sh
git tag -a v1.1-<lot> -m "Module project 1.1 — <lot>"
git push origin v1.1-<lot>
gh run watch   # la CI compile, vérifie et publie
```

Le workflow `.github/workflows/release.yml` :

- vérifie que `module.properties` declare bien `1.1` ;
- compile en `--release 8` et refuse un bytecode plus récent ;
- vérifie la présence des classes clés et de `column-labels.properties` ;
- publie `org.openconcerto.modules.project-1.1.jar` + son `.sha256` ;
- prend les notes de version dans `docs/release-<tag sans « v »>.md` (titre =
  premier titre de niveau 1 du fichier) — d'où le nom des fichiers de notes.

Ne jamais réutiliser un tag existant : le jar publié doit correspondre au
commit tagué.

## 7. Problèmes courants

| Message | Cause | Solution |
|---|---|---|
| `OpenConcerto jar not found` | `$OPENCONCERTO_JAR` vide et pas de jar local | laisser le script télécharger, ou définir `OPENCONCERTO_JAR` |
| `javac is required` / `Unable to detect javac version` | pas de JDK (seulement un JRE) | installer un **JDK** 8+ |
| `package org.openconcerto… does not exist` | compilation sans `OpenConcerto.jar` | passer par `scripts/build-jar-with-curl.sh` |
| `Unable to start JarModuleFactory … Already added ID_AFFAIRE` | jar antérieur au correctif de démarrage | installer un jar ≥ `v1.1-demarrage-corrige` |
| Le client ignore le module (`NO_FACTORY=[Module … v1.1]`) | version du jar incohérente avec `module.properties` | `sh scripts/fix-module-version.sh` |

Voir aussi : `docs/installation-du-jar.md` (côté client) et
`docs/release-process.md` (processus de livraison).
