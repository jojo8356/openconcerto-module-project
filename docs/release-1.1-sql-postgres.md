# Module project 1.1 — les comptages de la reprise passent PostgreSQL

Le menu annonçait « rien à reprendre » alors que 37 documents attendaient leur
affaire. La cause est maintenant connue **et corrigée** : les 19 requêtes de
comptage étaient refusées par PostgreSQL.

- **Jar** : `org.openconcerto.modules.project-1.1.jar` — **289 989 octets**
  (empreinte SHA-256 dans le fichier `.sha256` joint) ;
- **téléchargement** :
  <https://github.com/jojo8356/openconcerto-module-project/releases/download/v1.1-sql-postgres/org.openconcerto.modules.project-1.1.jar> ;
- **installation** : remplacer le jar du module dans `lib/` d'OpenConcerto,
  puis relancer le client (voir `docs/installation-du-jar.md`).

## Les deux fautes

Le message affiché dans votre fenêtre était exact : *« impossible d'accéder au
résultat de SELECT count(*) … »*. Les requêtes produites étaient invalides pour
PostgreSQL, pour deux raisons distinctes.

**1. Une table citée avant d'être jointe** (17 comptages de transfert) :

```sql
FROM "…"."TR_COMMANDE" ON "TR_COMMANDE"."ID_SAISIE_ACHAT" = "SAISIE_ACHAT"."ID"
                          AND "TR_COMMANDE"."ID_COMMANDE" = "COMMANDE"."ID"  -- COMMANDE pas encore jointe
INNER JOIN "…"."COMMANDE" ON …
```

PostgreSQL répond `invalid reference to FROM-clause entry for table "commande"`.

**2. Une colonne non qualifiée** (2 comptages de saisie d'achat) :

```sql
WHERE "SOURCE" = 'COMMANDE'
```

`SAISIE_ACHAT` et `COMMANDE` ont toutes deux une colonne `SOURCE` → `column
reference "SOURCE" is ambiguous`. Confirmé sur un PostgreSQL 16 réel : la même
requête, avec `"SAISIE_ACHAT"."SOURCE"`, s'exécute sans erreur.

**Pourquoi aucun test ne l'avait vu :** SQLite, utilisé pour les tests sans
base, accepte les deux. Les tests étaient verts, la production refusait.

## Le correctif

- la jointure est découpée : chaque `ON` ne cite que les tables déjà jointes ;
- `SOURCE` est qualifiée par sa table ;
- un **contrôle de portée** lint désormais toutes les requêtes du plan
  (`tests/cli/sql_scope.py`), avec les deux requêtes cassées comme cas de
  référence — il échoue si le défaut revient.

## Vérifié

- `tests/cli/sql_scope.py --selftest` : **8 contrôles** (les deux pièges
  détectés, les deux versions corrigées acceptées) ;
- `sh scripts/test-affaire-cli.sh` : **85 contrôles** SQL, le plan passé au
  contrôle de portée, et le test bout-en-bout dans SQLite ;
- `AffairBackfillSupportTest` : **73 contrôles**, dont 8 sur la forme des
  requêtes ; `AffairRepairReportTest` : **31 contrôles** ;
- les 6 fichiers SQL exécutés sur **PostgreSQL 16** dans la CI (run
  `41112426597`, vert).

## Résultat sur votre base (30 octobre)

Le menu et le SQL annoncent maintenant **le même nombre, 37** :

| Reprise | Documents |
| --- | --- |
| `COMMANDE_CLIENT <- DEVIS` (via `TR_DEVIS`) | 8 |
| `BON_DE_LIVRAISON <- COMMANDE_CLIENT` (via `TR_COMMANDE_CLIENT`) | 1 |
| `SAISIE_VENTE_FACTURE <- BON_DE_LIVRAISON` (via `TR_BON_DE_LIVRAISON`) | 17 |
| `AVOIR_CLIENT <- SAISIE_VENTE_FACTURE` (via `TR_SAISIE_VENTE_FACTURE`) | 3 |
| `BON_DE_LIVRAISON <- SAISIE_VENTE_FACTURE` (via `TR_SAISIE_VENTE_FACTURE`) | 8 |
| **Total** | **37** |

Les 17 factures fournisseur et les 8 avoirs annoncés la veille par le diagnostic
n'étaient donc pas réels : c'étaient des lignes de `TR_*` pointant l'affaire
« Indéfini ». Il n'y a **aucune facture fournisseur** à reprendre.

## Le test à faire

1. Installer ce jar, relancer le client.
2. `Aide > Reprendre les affaires des documents` → il doit annoncer **37**.
3. Valider, puis :
   ```sh
   docker exec -i openconcerto176-db-1 sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < /tmp/attendu.sql
   ```
   doit afficher **0**.
4. Affaire **12085** → onglet **Factures fournisseurs** : **24 lignes**, colonne
   **Affaire** = `12085`. La base en compte **25** : la 25ᵉ
   (`F201240028467`, ID 27) est **archivée** (`ARCHIVE = 1`), et OpenConcerto ne
   montre pas les documents archivés. Vérifié le 30/10 : ce n'est pas un défaut,
   les 25 sont bien rattachées à l'affaire.

Si un comptage échoue encore, la fenêtre affiche désormais la cause exacte et
`~/openconcerto-reprise-affaires.log` contient les 19 requêtes avec leur erreur.
