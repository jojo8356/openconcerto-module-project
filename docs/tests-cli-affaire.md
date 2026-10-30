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

Sans JDK sur la machine, les deux étages Java tournent dans un conteneur
jetable (`eclipse-temurin:8-jdk`) dès que Docker est disponible ; sinon ils sont
ignorés et les contrôles SQL tournent quand même. `--dry-run` montre les
commandes sans rien exécuter.

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

### 4. Les quatre fichiers SQL (`tools/oc_sql_sqlite.py`)

Ils sont **générés depuis le code** : `tools/genere_sql_affaire.py` lit
`AffairTransferSupport.TRANSFER_PAIRS` et `ItemAffairColumnRules.PARENTS`, écrit
les fichiers, et `--check` échoue si le SQL a dérivé du code. Il y en a quatre
parce que, sur la base du client, seuls `FACTURE_FOURNISSEUR_ELEMENT` et
`DEMANDE_ACHAT_ELEMENT` portent la colonne `ID_AFFAIRE` :

| Fichier | Contenu | Sûr sur |
| --- | --- | --- |
| `sql/diagnostic-affaire-transfert.sql` | en-têtes (17 transferts, 2 saisies) | toute base |
| `sql/reprise-affaire-transfert.sql` | en-têtes, une transaction | toute base |
| `sql/diagnostic-affaire-lignes.sql` | 12 tableaux de lignes | seulement là où la colonne existe |
| `sql/reprise-affaire-lignes.sql` | 12 tableaux, **un bloc = une transaction** | idem |

Les anciens fichiers touchaient les 12 tableaux de lignes en une seule
transaction : sur la base du client, `column ... does not exist` annulait
**aussi** la reprise des en-têtes. C'est ce que la mesure d'`information_schema`
a révélé, et c'est désormais reproduit dans le test (schéma « client » à deux
tableaux, puis variante à douze).

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

## La fenêtre « Historique affaires » : quoi tester, et contre quoi comparer

Cette fenêtre ne montre que les documents **rattachés à l'affaire
sélectionnée**. Une affaire sans document affiche donc 0 partout : ce n'est pas
un défaut, et ça ne prouve rien. Il faut d'abord choisir une affaire qui a des
documents.

```sh
# 1. éditer le numéro d'affaire dans le fichier (une seule ligne), puis :
sh scripts/oc-psql.sh -f sql/historique-affaire.sql

# si scripts/oc-psql.sh n'existe pas dans votre copie, ou si la base tourne
# dans un conteneur dont le nom n'est pas « postgres » :
docker ps --format '{{.Names}} | {{.Image}} | {{.Ports}}'   # repérer le conteneur de la base
docker exec -i NOM_DU_CONTENEUR sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < fichier.sql
```

Le conteneur connaît son rôle et sa base : `psql -U "$POSTGRES_USER" -d
"$POSTGRES_DB"` évite de deviner. Cas rencontré : conteneur
`openconcerto176-db-1`, image `openconcerto176-db` (un `grep postgres` ne le
trouve pas), port 5433.

Pour choisir une affaire qui a réellement des documents :

```sql
select "ID_AFFAIRE", count(*) as factures
  from "OpenConcerto42"."FACTURE_FOURNISSEUR"
 where "ID_AFFAIRE" > 1
 group by 1 order by 2 desc limit 10;
```

Le fichier est en **lecture seule** et donne, pour cette affaire :

- le nombre de documents **par table** — donc par onglet de la fenêtre ;
- le détail (ID, numéro, affaire) ;
- et, en fin de sortie, le rappel des documents sans affaire à reprendre.

Comparaison : si un onglet est vide alors que la table correspondante a des
lignes dans cette sortie, c'est un défaut d'affichage ou de lien, pas une
absence de données.

### Deux pièges de cette fenêtre

- **« Masquer dossiers clos »** est coché par défaut : une affaire clôturée
  n'apparaît **pas** dans la liste de gauche, même si elle a des documents.
  Décochez-le avant de conclure.
- la liste de gauche affiche `date + NUMERO + NOM`, **pas** l'`ID`. Pour
  l'affaire d'identifiant `190`, le numéro est `12085` : c'est `12085` qu'il faut
  chercher, et si `NOM` est vide la ligne est courte et facile à manquer.

### Les contrôles à faire dans la fenêtre, dans cet ordre

| # | Action | Résultat attendu |
| --- | --- | --- |
| H1 | choisir une affaire **avec** documents (voir la sortie SQL) | la liste se remplit, les totaux du bas ne sont plus à 0,00 € |
| H2 | passer chaque onglet (Devis, Bons de commande, Bons de réception fournisseurs, Factures, Avoirs, Demandes d'achat, Demandes de prix, Bons de livraison clients, Achats, Commandes fournisseurs…) | les compteurs correspondent à la sortie SQL, ligne pour ligne |
| H3 | sur chaque onglet, lire la dernière colonne **Affaire** | elle porte le numéro de l'affaire, jamais vide sur une ligne affichée |
| H4 | cliquer sur l'en-tête **Affaire** | tri croissant puis décroissant, aucune exception |
| H5 | sélectionner une ligne | les boutons **Transfert vers facture**, **Transfert vers commande client**, **Modifier le document…** et **Modifier l'affaire** deviennent actifs (plus grisés) |
| H6 | **Modifier l'affaire** → choisir une autre affaire → OK | la ligne quitte la liste de l'affaire courante ; en fermant/rouvrant la fenêtre, elle est sous la nouvelle affaire |
| H7 | double-clic sur une facture issue d'un transfert | le formulaire s'ouvre avec le champ **Affaire** déjà rempli du même numéro (c'est le défaut d'origine) |
| H8 | **Fermer** (bouton et croix de la fenêtre) | aucune fenêtre d'erreur, aucune trace `UncaughtException` dans le journal |

Si H2/H3 échouent, envoyez-moi : la capture de l'onglet, la sortie de
`sql/historique-affaire.sql` et le numéro d'affaire. La comparaison dit tout de
suite si la donnée manque ou si c'est l'affichage.

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
| `sql/historique-affaire.sql` | ce que la fenêtre Historique affaires **devrait** afficher |
| `.github/workflows/ci-cd.yml` (job `cli-affaire`) | rejoue tout à chaque PR, plus PostgreSQL 16 |
