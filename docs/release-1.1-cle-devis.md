# Module project 1.1 — la clé du devis est `ID_DEVIS`

Ce jar corrige la reprise des documents issus d'un **devis**. C'est le
troisième défaut trouvé en mesurant la base réelle, après les tableaux de lignes
sans colonne et l'absence de colonne `ID` sur `DEVIS`.

- **Jar** : `org.openconcerto.modules.project-1.1.jar` (empreinte SHA-256 dans
  le fichier `.sha256` joint) ;
- **téléchargement** :
  <https://github.com/jojo8356/openconcerto-module-project/releases/download/v1.1-cle-devis/org.openconcerto.modules.project-1.1.jar>
- **installation** : remplacer le jar du module dans `lib/` d'OpenConcerto,
  puis relancer le client (voir `docs/installation-du-jar.md`).

## Le défaut

Sur votre base, `DEVIS` n'a **pas** de colonne `ID` : sa clé est `ID_DEVIS`
(46 colonnes, 381 devis, 291 lignes de `TR_DEVIS`). Or la reprise joint chaque
table de transfert sur la clé `ID` de sa source :

```sql
-- avant : echoue sur votre base
JOIN "DEVIS" ON "DEVIS"."ID" = "TR_DEVIS"."ID_DEVIS"
```

Les **4 transferts partant d'un devis** n'étaient donc jamais réparés :
`DEVIS → COMMANDE`, `→ COMMANDE_CLIENT`, `→ SAISIE_VENTE_FACTURE`,
`→ BON_DE_LIVRAISON`. Soit, au prorata de vos données, la plus grosse part des
documents clients concernés.

## Le correctif

`AffairBackfillSupport.keyOf(schema, table)` cherche la clé dans cet ordre :
`ID`, puis `ID_<TABLE>`, sinon la paire est ignorée (aucune requête vouée à
l'échec). La même règle est appliquée aux trois étapes (source `SOURCE`/
`IDSOURCE`, tables `TR_*`, lignes) et aux fichiers SQL, désormais **générés
depuis le code** (`tools/genere_sql_affaire.py`, 6 fichiers).

## Vérifié

- **85 contrôles** exécutés sans base (`sh scripts/test-affaire-cli.sh`), dont :
  jointure sur `ID_DEVIS` et **jamais** sur `ID`, variante « aucune clé » où
  seuls les blocs du devis échouent sans annuler les autres ;
- les 6 fichiers SQL exécutés sur un **PostgreSQL 16** réel, dans la CI ;
- les 8 suites unitaires du module, dont `AffairBackfillSupportTest` enrichi de
  la clé du devis.

## Le test à faire, sur votre base

```sh
# 1. ce que le menu doit annoncer (lecture seule)
docker exec -i openconcerto176-db-1 sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < sql/attendu-reprise.sql

# 2. Aide > Reprendre les affaires des documents : le nombre annonce doit
#    etre egal au total ci-dessus. Si oui, confirmer.

# 3. apres confirmation, relancer la meme commande : le total doit tomber a 0
```

Ce qui reste sans affaire ensuite, ce sont les documents saisis à la main :
ils n'ont pas de document d'origine, il n'y a rien à reprendre.
