# Paramètres — libellés des colonnes (pour toute l'équipe)

Le menu **Paramètres → Affichage → Libellés des colonnes** permet à la personne
qui a **le plus de droits dans la base** de choisir le nom des colonnes affichées
dans les listes de l'ERP, **pour tout le monde**.

Cas d'origine : dans les listes, certaines colonnes s'affichent avec leur nom
technique (`ID_CLIENT`, `ID_FACTURE_FOURNISSEUR`, `ID_AFFAIRE`). Pour une
utilisatrice métier c'est illisible : elle veut voir `CLIENT`, `FACTURE
FOURNISSEUR`, `AFFAIRE`.

---

## 1. Ce que voit l'utilisateur

| Avant | Après |
|---|---|
| `ID_CLIENT` | `CLIENT` |
| `ID_AFFAIRE` | `AFFAIRE` |
| `ID_FACTURE_FOURNISSEUR` | `FACTURE FOURNISSEUR` |
| `TOTAL_HT`, `DATE` | inchangés (ce n'est pas une clé étrangère) |

La transformation est **automatique** dès l'installation (mode `AUTO`, décrit
plus bas) : la suppression du préfixe `ID_` est appliquée partout, sans rien
paramétrer. L'écran sert aux **exceptions** : un libellé différent selon la
table, une abréviation, un libellé métier (`N° de devis`), ou le retour en
arrière.

## 2. Qui peut ouvrir l'écran

Le menu n'est proposé qu'à l'utilisateur qui a le plus de droits dans la base,
dans cet ordre :

1. les **super-utilisateurs** (`USER_COMMON.SUPERUSER`) s'il y en a ;
2. sinon les **administrateurs** (`USER_COMMON.ADMIN`) ;
3. sinon le ou les utilisateurs qui cumulent **le plus de droits** accordés dans
   `USER_RIGHT`.

Les comptes désactivés (`IS_ACTIVE = false`) sont ignorés. S'il n'y a aucune
table de droits (installation sans gestion des droits), OpenConcerto considère
que tout est permis : l'écran est alors ouvert, comme le reste de l'ERP.

Pour les autres utilisateurs, le menu **n'apparaît pas**. S'ils forcent
l'ouverture, un message explique qui a le droit et pourquoi.

> Le journal du client trace la décision au démarrage :
> `[module project] menu « Libellés des colonnes » masque : acces refuse : le role le plus haut est Gisèle (superutilisateur, 5 droits)`

## 3. Où le réglage est enregistré : serveur SQL **et** jar

| Emplacement | Rôle | Qui gagne |
|---|---|---|
| **Serveur SQL** — tables `PROJECT_COLUMN_LABEL` et `PROJECT_SETTINGS`, dans le schéma de la société | source de vérité du quotidien ; s'applique à **tous les postes** de l'équipe | prioritaire |
| **Jar** — fichier `column-labels.properties` embarqué | valeurs par défaut d'une nouvelle installation, ou libellés figés dans une version livrée | complété par la base |

Le choix fait dans l'écran est écrit **sur le serveur**, jamais dans un fichier
du poste : la collègue qui se connecte le lendemain voit les mêmes noms.

Les deux tables :

```sql
PROJECT_COLUMN_LABEL   ID, TABLE_NAME, COLUMN_NAME, LABEL, DATE, ID_USER
PROJECT_SETTINGS       KEY, VALUE, DATE, ID_USER      -- dont column.label.mode
```

- clé unique `(TABLE_NAME, COLUMN_NAME)` : impossible d'avoir deux libellés
  concurrents pour la même colonne ;
- `TABLE_NAME = '*'` : la règle vaut pour cette colonne dans **toutes** les
  tables (une seule saisie pour `ID_CLIENT`) ;
- `DATE` / `ID_USER` : trace de qui a changé quoi, quand.

## 4. Les trois modes

| Mode | Effet |
|---|---|
| `AUTO` *(défaut)* | applique les règles saisies **puis** retire le `ID_` des autres colonnes |
| `MAPPING` | applique **uniquement** les règles saisies, ne touche à rien d'autre |
| `OFF` | aucun changement : les noms techniques réapparaissent (retour en arrière immédiat) |

L'ordre de résolution est fixe : `TABLE.COLONNE` → `*.COLONNE` →
suppression du `ID_` (si `AUTO`) → nom d'origine.

## 5. Utiliser l'écran

1. Menu **Paramètres → Affichage → Libellés des colonnes**.
2. La liste montre toutes les colonnes techniques (`ID_…`) des tables, avec :
   - **Table**, **Colonne** (nom technique, non modifiable) ;
   - **Aperçu** : ce qui sera affiché si on laisse la case vide ;
   - **Libellé affiché** : la case à remplir.
3. Champ **Filtrer** : taper `facture` ou `client` pour trouver la ligne.
4. **Ajouter une colonne…** : pour une règle qui n'apparaît pas dans la liste
   (ou pour `*` = toutes les tables).
5. **Supprimer la règle** : revient au libellé automatique pour cette ligne.
6. **Enregistrer pour l'équipe** : écrit en base, puis met à jour les listes
   déjà ouvertes sur ce poste. Les autres postes verront le changement au
   prochain démarrage du client.
7. **Exporter pour le jar…** : écrit un fichier `column-labels.properties` à
   poser dans `src/org/openconcerto/modules/project/` avant de reconstruire le
   jar (pour une nouvelle installation, ou pour figer les libellés d'une
   version livrée).

## 6. Ce qui est couvert à l'écran

Le renommage est appliqué **sans modifier le cœur OpenConcerto**, à deux
niveaux :

1. **modèle des listes** de l'historique des affaires (le module les construit) :
   l'en-tête *et* la recherche utilisent le nouveau libellé ;
2. **en-têtes de tous les tableaux** de l'application, y compris les listes du
   cœur : un écouteur global renomme la valeur d'en-tête dès qu'un tableau
   apparaît, et la réapplique quand le modèle change.

Limite connue, documentée : pour une colonne dont la table n'est pas connue de
l'écran (listes du cœur), seules la règle `*.COLONNE` et la règle automatique
s'appliquent ; une règle propre à une table (`COMMANDE.ID_AFFAIRE`) est
appliquée dans l'historique des affaires et dans les listes du module, pas dans
une liste du cœur où la table n'est pas identifiable.

## 7. Vérifications exécutables

```sh
sh tests/sql/e2e-colonnes.sh          # 34 contrôles SQL (pglite)
sh scripts/test-mutations-colonnes.sh # prouve que ces tests savent échouer
sh scripts/run-tests.sh               # dont ColumnLabelRulesTest (39 tests)
```

Ce que couvre chaque suite :

| Suite | Contrôles |
|---|---|
| `ColumnLabelRulesTest` | suppression du `ID_`, ordre de résolution, modes, validation des libellés, choix du rôle le plus haut, SQL de création/enregistrement, non-dérive avec le fichier SQL de référence |
| `e2e-colonnes.sh` (34) | migration idempotente, unicité `(table, colonne)`, règle `*` + règle par table, enregistrement transactionnel (état préservé en cas d'erreur), UTF-8, requête « qui a le plus de droits » (superutilisateur > administrateur > nombre de droits, comptes désactivés ignorés), aucune table du cœur touchée |
| `test-mutations-colonnes.sh` (7) | le préfixe qui n'est plus retiré, le mode `AUTO` ignoré, le mauvais rôle choisi, la dérive Java/SQL, l'index qui n'est plus unique, l'enregistrement sans transaction : **tous détectés** |

## 8. Dépannage

| Symptôme | Cause probable | Que faire |
|---|---|---|
| Le menu n'apparaît pas | l'utilisateur courant n'est pas le mieux doté | lire la ligne `[module project] menu « Libellés des colonnes » masque : …` dans la console |
| Les libellés ne changent pas | mode `OFF` en base | vérifier `PROJECT_SETTINGS` (`column.label.mode`) |
| Un poste garde les anciens noms | client pas encore redémarré | redémarrer le client (les libellés sont lus au démarrage) |
| Les tables n'existent pas | migration impossible (droits SQL) | lancer `tests/sql/migration-colonnes.sql` avec un compte administrateur de la base |
| Le libellé saisi est refusé | vide, > 128 caractères, ou caractère de contrôle | corriger la saisie ; le message indique la ligne |

Retour arrière complet : passer le mode à `OFF` (les noms techniques
réapparaissent immédiatement), ou vider la table `PROJECT_COLUMN_LABEL`.
