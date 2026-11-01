# Correctif : une table de libellés vide empêchait OpenConcerto de démarrer

## Le symptôme

Deux fenêtres, dans cet ordre, et plus aucune connexion possible :

```
Impossible d'accéder aux préférences

Erreur de connexion
Constructor failed
Caused by: java.lang.IllegalStateException:
    No preferences for DBRoot SQLSchema OpenConcerto42
      at SQLPreferences.getMemCached(SQLPreferences.java:148)
      at ReferenceArticleSQLElement.<init>(ReferenceArticleSQLElement.java:168)
      at ComptaPropsConfiguration.setSocieteDirectory(ComptaPropsConfiguration.java:949)
```

Ces trois messages désignent tous le même incident, mais **aucun ne dit la
cause**.

## La cause réelle

Le journal du client (`logs/<poste>/OpenConcerto-0-age0.log`) la donne :

```
java.lang.IllegalStateException: /PROJECT_COLUMN_LABEL/ is empty, can not infer UNDEFINED_ID
    at org.openconcerto.sql.model.SQLTable.findMinID(SQLTable.java:603)
    at org.openconcerto.sql.model.SQLTable.fetchUndefID(SQLTable.java:580)
    at org.openconcerto.sql.replication.MemoryRep.replicateStruct(MemoryRep.java:334)
    at org.openconcerto.sql.preferences.SQLPreferences.startMemCached(SQLPreferences.java:125)
    at org.openconcerto.erp.config.ComptaPropsConfiguration.setUpSocieteDataBaseConnexion(...)
```

OpenConcerto a besoin, pour **chaque table dont la clé primaire est numérique**,
d'un « identifiant non défini » (`SQLTable.isRowable()`). Quand la politique est
`min` (propriété `fwk_sql.debug.undefined_id`, ou métadonnée `undefined ID
policy` du schéma), il exécute :

```sql
select min("ID") from "OpenConcerto42"."PROJECT_COLUMN_LABEL";
```

Sur une table **vide**, `min()` vaut `NULL` → exception. La chaîne :

1. `startMemCached` échoue → le `try/catch` de `NouvelleConnexionAction` avale
   l'erreur (« don't die now, we might not need them ») et affiche seulement
   « Impossible d'accéder aux préférences » ;
2. le cache des préférences reste vide ;
3. `setSocieteDirectory` construit `ReferenceArticleSQLElement`, qui lit une
   préférence → `No preferences for DBRoot` ;
4. `Constructor failed` → « Erreur de connexion ».

Autrement dit : **la table des libellés du module était vide, et cela suffisait
à empêcher le client de démarrer.**

## Pourquoi elle était vide

`ColumnLabelRules.saveStatements` faisait un remplacement complet :

```sql
delete from "PROJECT_COLUMN_LABEL";
insert into "PROJECT_COLUMN_LABEL" ...   -- une ligne par libellé
```

Dès qu'aucun libellé n'était enregistré (premier usage, ou après suppression de
toutes les règles), la table restait vide — et le démarrage suivant échouait.

## Le correctif

### 1. Une ligne sentinelle, jamais supprimée

```sql
insert into "PROJECT_COLUMN_LABEL" ("TABLE_NAME", "COLUMN_NAME", "LABEL")
select '', '', ''
where not exists (select 1 from "PROJECT_COLUMN_LABEL");
```

- créée avec les tables (`ColumnLabelRules.sentinelStatement`), donc une base
  neuve est correcte dès l'installation ;
- conservée à chaque enregistrement : le `delete` devient
  `delete from ... where not ("TABLE_NAME" = '' and "COLUMN_NAME" = '')` ;
- remise si la table a été vidée (`ColumnLabelRules.saveStatements`) ;
- **jamais lue comme une règle** : la requête de lecture exclut la sentinelle
  (`ColumnLabelRules.sentinelCondition`), et `ColumnLabelStore` ignore aussi les
  noms vides par sécurité.

### 2. Réparation d'une base déjà bloquée

```sh
docker exec -i $C sh -c 'psql -U "$POSTGRES_USER" -d dump1009' \
    < sql/fix-project-column-label-undefined-row.sql
```

Le fichier insère la sentinelle, affiche `min("ID")`, puis **liste toutes les
autres tables à clé numérique vides du schéma** : ce sont elles qui bloquent un
démarrage, et il ne doit plus en rester aucune.

Il est idempotent : une seconde exécution ne change rien.

## Ce qui est testé

| Test | Ce qu'il vérifie |
| --- | --- |
| `ColumnLabelRulesTest.testLabelTableIsNeverEmpty` | la sentinelle est créée avec les tables, conservée à l'enregistrement, et exclue de la lecture |
| `ColumnLabelRulesTest.testCreateStatementsAreIdempotentAndSchemaQualified` | 4 instructions, toutes qualifiées par le schéma |
| `tests/sql/e2e-colonnes.sh` | après migration, `select min("ID")` est calculable et la sentinelle n'est pas une règle |
| mutation 20 | supprimer la création de la sentinelle fait échouer la suite |
| mutation 21 | effacer la sentinelle à chaque enregistrement fait échouer la suite |
| CI « Correctif - table des libelles vide » | reproduit la panne sur PostgreSQL 16 (table vide → `min(ID)` NULL), la détecte par le diagnostic, applique le correctif, vérifie l'idempotence |

## À retenir pour la suite

Toute table créée par un module avec une clé primaire `serial` doit contenir au
moins une ligne, en permanence. Sinon, un poste peut ne plus démarrer du tout —
sans message qui parle de cette table.
