## Le symptôme de départ

> « Quand on modifie une facture fournisseur ou une commande fournisseur avec
> l'`id_affaire`, elle ne s'affiche pas. »

L'audit a montré que l'affaire était perdue **à la création par transfert**, et
que la reprise censée réparer les documents existants était elle-même cassée.
Six défauts distincts, tous mesurés sur la base du client, ont dû être corrigés
en cascade — chacun masquait le suivant.

## Les six défauts et leurs correctifs

| # | Défaut | Effet constaté | Correctif |
| --- | --- | --- | --- |
| 1 | Les injecteurs de transfert ne déclaraient pas `ID_AFFAIRE` | la facture issue d'une commande perdait l'affaire | `AffairTransferSupport` : 17 paires corrigées, colonne **Affaire** en lecture seule |
| 2 | Les fichiers SQL touchaient 12 tableaux de lignes, dont 10 sans la colonne | une table absente annulait **toutes** les reprises (transaction unique) | SQL **générés** depuis le code (`tools/genere_sql_affaire.py`), **un bloc par transaction** |
| 3 | `DEVIS` n'a pas de colonne `ID` (sa clé est `ID_DEVIS`) | les 4 transferts du devis échouaient | `keyOf()` : `ID`, sinon `ID_<TABLE>`, sinon paire ignorée |
| 4 | La ligne « Indéfini » (ID 1) était comptée comme un document | 200 « saisies à réparer » au lieu de 3 | garde-fou `<clé> > 1` partout (cible, source, lien, ligne) |
| 5 | Un comptage en échec était avalé et valait `0` | le menu annonçait « rien à reprendre » | `AffairRepairReport` : une erreur ne peut plus produire ce message |
| 6 | Le SQL produit était refusé par PostgreSQL | les 19 comptages échouaient (d'où le n° 5) | `ON` découpé par table jointe, colonne `SOURCE` qualifiée |

Le n° 6 mérite un mot : **SQLite acceptait ces requêtes**, donc tous les tests
étaient verts alors que la production refusait. C'est exactement le trou que ce
lot bouche.

## Résultat sur la base du client (30/10)

```
menu Aide > Reprendre les affaires des documents .... 37
compte rendu de la reprise ......................... 37 lignes rattachées
sql/attendu-reprise.sql après reprise .............. 0
```

Détail des 37 : 8 `COMMANDE_CLIENT` depuis un devis, 1 `BON_DE_LIVRAISON` depuis
une commande client, 17 `SAISIE_VENTE_FACTURE` depuis un bon de livraison,
3 `AVOIR_CLIENT` et 8 `BON_DE_LIVRAISON` depuis une facture. Aucune facture
fournisseur : les 17 annoncés par un premier diagnostic étaient des lignes
`TR_*` pointant l'affaire « Indéfini ».

L'affaire 12085 compte **25 factures fournisseur en base**, **24 affichées** : la
25ᵉ (`F201240028467`) porte `ARCHIVE = 1`, et OpenConcerto ne montre pas les
archives. Vérifié, ce n'est pas un défaut.

## Tests, tous exécutables en ligne de commande

```sh
sh scripts/test-affaire-cli.sh        # 6 étages : transfert, plan du module, SQLite, portée, SQL, historique
python3 tools/oc_sql_sqlite.py        # 85 contrôles, 6 fichiers SQL du module exécutés
python3 tests/cli/sql_scope.py --selftest   # 8 contrôles : les 2 requêtes cassées en cas de référence
sh scripts/run-tests.sh               # 9 suites, dont AffairBackfillSupportTest (73) et AffairRepairReportTest (31)
```

- les 6 fichiers SQL sont exécutés **sur un PostgreSQL 16 réel** dans la CI
  (`scripts/oc-sql-file.sh --postgres`) ;
- `tools/genere_sql_affaire.py --check` échoue si le SQL dérive du code ;
- le plan produit par le module lui-même (pas une copie) est rejoué dans SQLite
  **et** passé au contrôle de portée.

## Documentation

`CHANGELOG.md` (6 sections datées, avec les mesures), `docs/release-1.1-*.md`
(notes de chaque release), `docs/tests-cli-affaire.md` (comment rejouer les
tests), et les 3 nouveaux fichiers de contrôle :
`sql/controle-affaire-12085.sql`, `sql/diagnostic-facture-absente.sql`,
`tests/cli/sql_scope.py`.

## Livraisons

10 releases `v1.1-…`, la dernière `v1.1-sql-postgres` (jar Java 8, 289 989
octets) — chacune testée, aucune n'écrase un tag existant, la version du module
reste `1.1` comme demandé.

## Points de vigilance pour la relecture

- **ne jamais retirer les garde-fous `> 1`** : les clés étrangères non
  renseignées valent 1, pas `NULL` ; c'est le défaut n° 4 ;
- **ne pas tester le SQL uniquement sur SQLite** : il accepte ce que PostgreSQL
  refuse ; `tests/cli/sql_scope.py` existe pour ça ;
- `DEVIS` : sa clé est `ID_DEVIS`, pas `ID`.
