# Module project 1.1 — la ligne « Indéfini » n'est plus comptée

Ce jar corrige le **quatrième** défaut trouvé en mesurant votre base, et de loin
le plus trompeur : la reprise comptait la ligne « Indéfini » de chaque table.

- **Jar** : `org.openconcerto.modules.project-1.1.jar` — **287 478 octets**
  (empreinte SHA-256 dans le fichier `.sha256` joint) ;
- **téléchargement** :
  <https://github.com/jojo8356/openconcerto-module-project/releases/download/v1.1-indefini/org.openconcerto.modules.project-1.1.jar>
- **installation** : remplacer le jar du module dans `lib/` d'OpenConcerto,
  puis relancer le client (voir `docs/installation-du-jar.md`).

## Le défaut

Chaque table d'OpenConcerto contient une ligne **« Indéfini », d'identifiant 1**.
Et une clé étrangère non renseignée vaut **`1`**, jamais `NULL`.

Le diagnostic supposait l'inverse. Il comptait donc, par exemple :

```sql
-- avant : chaque ligne de TR_COMMANDE dont la cible n'est pas renseignee
-- (ID_SAISIE_ACHAT = 1) est comptee comme « une saisie d'achat a reparer »
SELECT count(*) FROM "TR_COMMANDE"
JOIN "SAISIE_ACHAT" ON "SAISIE_ACHAT"."ID" = "TR_COMMANDE"."ID_SAISIE_ACHAT"
WHERE "SAISIE_ACHAT"."ID_AFFAIRE" IS NULL OR "SAISIE_ACHAT"."ID_AFFAIRE" <= 1;
```

Résultat sur votre base : **200 saisies d'achat « à réparer »** et **200 bons de
réception « à réparer »**, alors que vous n'avez que **3** saisies d'achat et
**10** bons de réception sans affaire. Les 200 étaient la même ligne 1, comptée
autant de fois qu'il y a de lignes de transfert.

Deux conséquences, toutes les deux visibles dans l'interface :

1. le menu `Aide > Reprendre les affaires des documents` annonçait un total
   sans rapport avec la réalité (le total de `sql/attendu-reprise.sql`,
   **462**, est faux pour la même raison : il a été mesuré avant ce correctif) ;
2. le `UPDATE` de reprise pouvait écrire sur la ligne 1 des tables, c'est-à-dire
   sur « Indéfini » elle-même.

## Le correctif

Une seule règle, appliquée partout : **une cible, une source, un lien ou une
ligne ne compte que si sa clé est strictement supérieure à 1.**

- `AffairBackfillSupport.realKey(quoter, table, key)` produit ce garde-fou
  (`"TABLE"."ID" > 1`) et `1 = 1` si la table n'a pas de clé connue ;
- il est appliqué aux **trois** étapes de la reprise — source `SOURCE`/`IDSOURCE`,
  tables `TR_*` (cible **et** source) et tableaux de lignes (lien **et**
  document) — ainsi qu'à l'étape `addSourceRepairs`, qui exige maintenant une
  clé réelle des deux côtés ;
- les **6 fichiers SQL** sont générés depuis ce code (`tools/genere_sql_affaire.py`)
  et portent les mêmes garde-fous : `reprise-affaire-transfert.sql`,
  `diagnostic-affaire-transfert.sql`, `reprise-affaire-lignes.sql`,
  `diagnostic-affaire-lignes.sql`, `historique-affaire.sql`, `attendu-reprise.sql`.

## Vérifié

- **85 contrôles** exécutés sans base (`sh scripts/test-affaire-cli.sh`), dont la
  fixture qui reproduit votre cas : une ligne « Indéfini » par table et un
  `TR_COMMANDE` dont les trois clés valent `1`. Les contrôles vérifient à la
  fois que **rien de la ligne 1 n'est compté** et que **rien n'est écrit sur la
  ligne 1** ;
- le test unitaire `AffairBackfillSupportTest` gagne 7 vérifications
  (`testPlaceholderRowsAreIgnored`) : la cible, la source, le lien de transfert
  et le lien de ligne sont tous protégés ;
- les 6 fichiers SQL exécutés sur un **PostgreSQL 16** réel, dans la CI ;
- les 8 suites unitaires du module.

## Le test à faire, sur votre base

Le total est passé de **462 à 37** sur votre base : les 425 documents d'écart
n'étaient pas réels, ils venaient de la ligne « Indéfini ».

```sh
# 1. ce que le menu doit annoncer (lecture seule)
docker exec -i openconcerto176-db-1 sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < sql/attendu-reprise.sql

# 2. le detail, cas par cas (lecture seule)
docker exec -i openconcerto176-db-1 sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < sql/diagnostic-affaire-transfert.sql
```

**Mesuré sur votre base le 30 octobre, avec ce fichier corrigé : 37.** Le
fichier d'avant correctif annonçait 462 sur la même base, et le diagnostic
annonçait 200 saisies d'achat là où il n'y en a que 3 — c'est bien la ligne
« Indéfini » qui gonflait tout.

Les deux « 200 » ont disparu ; ce qui reste (37) est réel et réparable. Ce qui
n'a pas de document d'origine — 3 saisies d'achat, 10 bons de réception, 104
devis sans affaire — n'est pas compté, c'est normal.

```sh
# 3. le menu doit annoncer 37, puis :
docker exec -i openconcerto176-db-1 sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < sql/reprise-affaire-transfert.sql

# 4. relancer la commande 1 : le total doit tomber a 0 (37 documents repris)
```

Si le menu annonce autre chose que **37**, envoyez-moi les deux chiffres :
c'est le seul écart que je ne peux pas voir d'ici (et il viendrait de la lecture
du schéma par le module, pas des données).

Après la reprise, l'onglet **Factures fournisseurs** de l'affaire **12085** doit
afficher ses lignes, avec la colonne **Affaire** renseignée : c'est le contrôle
visuel qui prouve que les documents ont bien retrouvé leur affaire. Mesure du
30/10 : 25 factures en base, 24 affichées — la 25ᵉ (`F201240028467`) est
archivée (`ARCHIVE = 1`) et OpenConcerto masque les archives.
