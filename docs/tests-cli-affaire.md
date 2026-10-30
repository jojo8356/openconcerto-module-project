# Tester l'affaire en ligne de commande, sans interface

Ce document remplace la vérification à la main : tout ce qui est décrit ici
s'exécute en une commande, affiche **OK / ÉCHEC** ligne par ligne, et ne touche
ni OpenConcerto, ni la base du client.

## La commande unique

```sh
sh scripts/test-affaire-cli.sh
```

Sortie attendue (extraits) :

```
=== 0. Compilation des tests en ligne de commande ===
   OK    compilation
=== 1. Transfert commande fournisseur -> facture ===
   OK   avant correctif, le coeur perd l'affaire
   OK   avant correctif, les autres champs sont bien copies
   OK   trois paires corrigees
   OK   apres correctif, l'affaire est transportee
   ...
   OK   affaire transportee par COMMANDE -> FACTURE_FOURNISSEUR
   OK   affaire transportee par COMMANDE -> BON_RECEPTION
=== 2. Plan de reprise ecrit par le module ===
   OK    29 reprises generees (29 tables decrites)
=== 3. Plan de reprise execute dans SQLite ===
   Controles : 49 | echecs : 0
=== 4. Fichiers SQL du module (sql/*.sql) ===
   Controles : 63 | echecs : 0
```

Code de sortie : `0` si tout est vert, `1` dès le premier échec. Aucune
installation, aucun serveur, aucun accès réseau.

Sans JDK, l'étage Java est ignoré et les contrôles SQL tournent quand même.

## Ce qui est réellement testé

### 1. Le transfert lui-même (`AffairTransferScenario`)

Le programme reproduit le scénario du client, avec les **mêmes règles que le
cœur** : des injecteurs qui déclarent leurs champs un par un, sans
`ID_AFFAIRE` — exactement comme les 26 injecteurs d'OpenConcerto 1.7.6.

1. commande fournisseur 251, affaire 11870 ;
2. transfert avec les règles du cœur → **l'affaire est perdue** (le bug est
   reproduit, pas seulement supposé) ;
3. `AffairTransferSupport.install(...)` → trois paires corrigées
   (`COMMANDE → SAISIE_ACHAT`, `→ FACTURE_FOURNISSEUR`, `→ BON_RECEPTION`) ;
4. même commande, même injecteur → **l'affaire est transportée** ;
5. robustesse : seconde application idempotente, aucun champ dupliqué,
   commande sans affaire → rien d'inventé, affaire « Indéfini » (1) transportée
   telle quelle, paire hors schéma signalée et non inventée.

### 2. Le plan de reprise (`AffairBackfillSqlDump`)

Le module **écrit lui-même** son plan : les requêtes de comptage et les `UPDATE`
viennent de `AffairBackfillSupport.plan()`, pas d'une copie écrite à la main.
Le programme les imprime (`TABLE`, `COUNT`, `UPDATE`) et le test Python les
exécute.

### 3. Le plan exécuté (`tests/cli/test-affaire-transfert.py`)

Sur les 49 contrôles, ceux qui comptent :

| Cas | Attendu |
| --- | --- |
| Facture née d'une commande qui porte une affaire | l'affaire est recopiée |
| Facture déjà rattachée à **une autre** affaire | jamais écrasée |
| Facture sans table de transfert | reste vide |
| Saisie d'achat née d'une commande (`SOURCE`/`IDSOURCE`) | affaire recopiée |
| Saisie d'achat dont la source est « Indéfini » (1) | rien |
| Saisie d'achat saisie à la main (sans source) | rien |
| Lignes de document sans affaire | reprennent celle du document |
| Ligne avec une affaire propre | conservée |
| Source pointant une affaire supprimée | la valeur est recopiée telle quelle |
| Seconde exécution | **aucune** écriture, compteurs à 0 |

L'ordre compte et il est vérifié : les documents sont repris **avant** les
lignes, sinon une ligne dont le document était vide ne serait jamais remplie.

### 4. Les vrais fichiers SQL (`tools/oc_sql_sqlite.py`)

`sql/diagnostic-affaire-transfert.sql` et `sql/reprise-affaire-transfert.sql`
sont exécutés **tels quels** (seules les commandes `\echo` de psql sont
retirées) dans une base SQLite qui porte le schéma `OpenConcerto42`, une
`INFORMATION_SCHEMA` minimale et la fonction `current_schema()`. 63 contrôles :

- le diagnostic compte juste, section par section (17 transferts, 12 tableaux
  de lignes, compteur global) ;
- le diagnostic n'écrit rien ;
- la reprise remplit ce qu'il faut, et **seulement** ce qu'il faut ;
- le rejeu ne change plus rien ;
- sans table `TR_*`, la reprise échoue et la transaction annulée ne laisse
  aucune écriture.

## Sur un vrai PostgreSQL

Deux façons, mêmes fichiers, mêmes contrôles :

```sh
# 1. conteneur jetable (Docker)
sh scripts/oc-sql-file.sh --docker

# 2. serveur déjà démarré, base JETABLE uniquement
PGHOST=localhost PGUSER=postgres PGPASSWORD=openconcerto PGDATABASE=oc_test \
  sh scripts/oc-sql-file.sh --postgres
```

Le script crée le schéma `OpenConcerto42` et y écrit : il refuse de continuer si
le schéma existe déjà. **Ne le pointez jamais sur la base du client.**

Sans Docker ni PostgreSQL :

```sh
sh scripts/oc-sql-file.sh --sqlite      # même scénario
sh scripts/oc-sql-file.sh --dry-run     # montre les commandes sans rien exécuter
```

Un seul fichier, pour l'inspecter :

```sh
sh scripts/oc-sql-file.sh --sqlite --file sql/diagnostic-affaire-transfert.sql
```

## Sur la base du client (lecture seule)

Rien à installer : `scripts/oc-psql.sh` parle directement au conteneur
PostgreSQL d'OpenConcerto.

```sh
# combien de documents ont perdu leur affaire ?
sh scripts/oc-psql.sh -f sql/diagnostic-affaire-transfert.sql

# puis, seulement si le diagnostic confirme :
sh scripts/oc-psql.sh -f sql/reprise-affaire-transfert.sql
```

Le diagnostic est en lecture seule. La reprise est dans une transaction
(`BEGIN … COMMIT`), idempotente, et ne remplit que les affaires vides.

## Ce qui reste à l'interface

Deux choses seulement, parce qu'elles dépendent de l'affichage :

- la colonne « Affaire » et le champ du formulaire après transfert
  (recette `docs/recette-graphique-gisele.md`, compte `abe`) ;
- le menu **Aide → Reprendre les affaires des documents** (comptage →
  confirmation → reprise → recomptage).

Tout le reste — transport de l'affaire, reprise des documents existants,
comportement du SQL sur PostgreSQL — est couvert ci-dessus.

## Fichiers

| Fichier | Rôle |
| --- | --- |
| `scripts/test-affaire-cli.sh` | enchaîne les quatre étages |
| `scripts/oc-sql-file.sh` | exécute `sql/*.sql` sur SQLite, Docker ou PostgreSQL |
| `tools/oc_sql_sqlite.py` | schéma de test, jeu de données, exécution, attentes |
| `tests/cli/test-affaire-transfert.py` | exécute le plan du module dans SQLite |
| `tests/org/.../AffairTransferScenario.java` | scénario de transfert (le bug puis le correctif) |
| `tests/org/.../AffairBackfillSqlDump.java` | imprime le plan de reprise du module |
| `.github/workflows/ci-cd.yml` (job `cli-affaire`) | rejoue tout à chaque PR, plus PostgreSQL 16 |
