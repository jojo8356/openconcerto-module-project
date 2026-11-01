# Module project 1.1 — tout se teste en ligne de commande

**Aucune règle n'a changé depuis `v1.1-transfert-affaire`** : le jar est
recompilé à partir des mêmes sources (même taille, 287 085 octets). Cette
version ne corrige pas le module, elle rend la précédente **vérifiable sans
interface**, chez vous, en une commande.

- **Jar** : `org.openconcerto.modules.project-1.1.jar` — **287 085 octets**
  (empreinte SHA-256 dans le fichier `.sha256` joint) ;
- **téléchargement** :
  <https://github.com/jojo8356/openconcerto-module-project/releases/download/v1.1-tests-cli/org.openconcerto.modules.project-1.1.jar>
- **fichiers SQL** (dans le dépôt, à ce tag) :
  [diagnostic-affaire-transfert.sql](https://github.com/jojo8356/openconcerto-module-project/blob/v1.1-tests-cli/sql/diagnostic-affaire-transfert.sql),
  [reprise-affaire-transfert.sql](https://github.com/jojo8356/openconcerto-module-project/blob/v1.1-tests-cli/sql/reprise-affaire-transfert.sql).

## Ce que vous pouvez lancer vous-même

### 1. Toute la chaîne, sans OpenConcerto ni base

```sh
sh scripts/test-affaire-cli.sh
```

Quatre étages, sortie **OK / ÉCHEC**, code 1 au premier échec. Si votre machine
n'a pas de JDK, les deux étages Java tournent seuls dans un conteneur
`eclipse-temurin:8-jdk` (Docker) ; `--dry-run` affiche les commandes :

1. **le transfert** : le programme reproduit le scénario (commande fournisseur
   avec affaire → facture) avec les règles du cœur, **constate la perte de
   l'affaire**, applique le correctif, rejoue le transfert et vérifie qu'elle
   arrive ; puis contrôle l'idempotence, l'affaire « Indéfini », la commande
   sans affaire et une paire hors schéma ;
2. **le plan de reprise** est écrit par le module lui-même
   (`AffairBackfillSupport.plan()`), pas recopié à la main ;
3. ce plan est **exécuté dans SQLite** : 49 contrôles (documents, « Indéfini »,
   affaire déjà remplie, source supprimée, absence de `TR_*`, rejeu sans
   écriture) ;
4. les **vrais fichiers `sql/*.sql`** sont exécutés : 63 contrôles.

### 2. Les fichiers SQL sur un vrai PostgreSQL

```sh
sh scripts/oc-sql-file.sh --docker     # conteneur jetable, rien à installer
sh scripts/oc-sql-file.sh --sqlite     # même scénario, sans Docker
sh scripts/oc-sql-file.sh --dry-run    # montre les commandes
```

Le script crée une base de test, y injecte les cas limites, exécute le
diagnostic, la reprise **deux fois** (idempotence) puis vérifie 41 valeurs. Il
refuse de s'exécuter si le schéma `OpenConcerto42` existe déjà : il ne peut pas
abîmer une base réelle.

### 3. Sur la base du client (lecture seule d'abord)

```sh
sh scripts/oc-psql.sh -f sql/diagnostic-affaire-transfert.sql
sh scripts/oc-psql.sh -f sql/reprise-affaire-transfert.sql   # écrit, transactionnel
```

## Corrigé depuis (même jar, SQL re-générés)

Les fichiers SQL ont été réécrits après une mesure sur la base du client : sur
les 12 tableaux de lignes, **seuls deux** (`FACTURE_FOURNISSEUR_ELEMENT`,
`DEMANDE_ACHAT_ELEMENT`) portent la colonne `ID_AFFAIRE`. Les fichiers
« reprise » et « diagnostic » touchaient les 12 en une seule transaction : le
`column ... does not exist` annulait **aussi** la reprise des en-têtes. Ils sont
maintenant quatre, **générés depuis le code**, et séparés :

| Fichier | Contenu | Sûr sur |
| --- | --- | --- |
| `sql/diagnostic-affaire-transfert.sql` | en-têtes | toute base |
| `sql/reprise-affaire-transfert.sql` | en-têtes, une transaction | toute base |
| `sql/diagnostic-affaire-lignes.sql` | tableaux de lignes | là où la colonne existe |
| `sql/reprise-affaire-lignes.sql` | un bloc = une transaction | là où la colonne existe |

`sql/attendu-reprise.sql` (nouveau) donne le nombre de documents que
**Aide → Reprendre les affaires** doit annoncer : à comparer avec ce que la
fenêtre affiche. Le test CLI exécute les cinq fichiers (73 contrôles).

## Corrigé dans cette version

- `sql/reprise-affaire-transfert.sql` ne traitait que **10** des **17** transferts
  du module et **3** des **12** tableaux de lignes. Il couvre maintenant tout,
  exactement comme `AffairTransferSupport.TRANSFER_PAIRS` et
  `ItemAffairColumnRules.LINE_TABLES`.
- `sql/diagnostic-affaire-transfert.sql` : `LIKE 'TR\\_%'` (barre oblique
  inversée doublée) ne listait **aucune** table de transfert ; corrigé, et la
  requête est vérifiée.
- Ces fichiers sont désormais exécutés à chaque PR, sur SQLite **et** sur
  PostgreSQL 16 (job `cli-affaire`), donc ils ne peuvent plus se désynchroniser
  du code sans que la CI passe au rouge.

## Documentation

`docs/tests-cli-affaire.md` : chaque commande, chaque contrôle, ce qui reste à
voir dans l'interface (colonne Affaire, menu de reprise) et pourquoi.
