# Paramètres — libellés des colonnes (pour toute l'équipe)

Le menu **Paramètres → Libellés des colonnes** permet à la personne
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

## 2. Où se trouve le menu

Le module crée un menu de premier niveau **Paramètres** dans la barre de menus,
**juste avant le menu « Aide »** (donc à droite de `Paye` et `Structure`) :

```
Fichier  Saisie  Gestion  Comptabilité  Déclaration  Statistiques  Paiement  Paye  Structure  Paramètres  Aide
                                                                                            └── Libellés des colonnes
```

(`Affichage` est un simple groupe de séparation interne : l'entrée apparaît
directement dans le menu `Paramètres`.)

Le menu est ajouté **après l'ouverture de la session**, parce que c'est à ce
moment-là que le client sait quel utilisateur est connecté. Tant que ce n'est
pas le cas, le module réessaie toutes les 2 secondes pendant 30 secondes : un
utilisateur inconnu n'est jamais interprété comme un refus (c'est ce qui faisait
disparaître le menu pour tout le monde).

Si le menu `Paramètres` ne peut pas être créé (version de client très
différente), l'entrée est ajoutée dans **Structure**.

## 3. Qui peut ouvrir l'écran

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

## 4. Où le réglage est enregistré : serveur SQL **et** jar

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

## 5. Les trois modes

| Mode | Effet |
|---|---|
| `AUTO` *(défaut)* | applique les règles saisies **puis** retire le `ID_` des autres colonnes |
| `MAPPING` | applique **uniquement** les règles saisies, ne touche à rien d'autre |
| `OFF` | aucun changement : les noms techniques réapparaissent (retour en arrière immédiat) |

L'ordre de résolution est fixe : `TABLE.COLONNE` → `*.COLONNE` →
suppression du `ID_` (si `AUTO`) → nom d'origine.

## 6. Utiliser l'écran

1. Menu **Paramètres → Libellés des colonnes**.
2. Le tableau montre **ce que voient les utilisateurs**, pas des cases vides :

| Colonne | Contenu |
|---|---|
| **Table** | table de la colonne (`*` = toutes les tables) |
| **Colonne** | nom technique (`ID_FOURNISSEUR`) — non modifiable |
| **Automatique** | ce que donnerait le mode automatique (ex. `FOURNISSEUR`) |
| **Libellé affiché (double-clic)** | **la valeur réellement affichée**, toujours en **noir** : **en gras** si elle est personnalisée, en texte normal si elle vient du mode automatique |

3. **Pour changer un nom : double-cliquez sur la case « Libellé affiché »**,
   tapez le nouveau texte, validez avec **Entrée** (Échap annule). Le texte
   existant est pré-sélectionné : taper remplace tout. On peut aussi sélectionner
   la case et taper directement, ou appuyer sur **F2**.
4. **Vider une case** (ou bouton **Réinitialiser (libellé auto)** sur une ou
   plusieurs lignes sélectionnées) = retour au libellé automatique
   (`ID_CLIENT` → `CLIENT`). Aucune règle inutile n'est enregistrée si le texte
   n'a pas changé.
5. Champ **Filtrer** : taper `facture` ou `client` pour trouver la ligne.
6. **Ajouter une colonne…** : pour une règle qui n'apparaît pas dans la liste
   (ou pour `*` = toutes les tables).
   **Appliquer à toutes les tables (*)** : prend la ligne sélectionnée et crée
   la règle `*.COLONNE` correspondante — la façon la plus rapide de renommer
   `ID_FOURNISSEUR` (ou `ID_CLIENT`, `ID_AFFAIRE`…) **partout** en une fois.
7. **Enregistrer pour l'équipe** : écrit en base, puis met à jour les listes
   déjà ouvertes sur ce poste. Les autres postes verront le changement au
   prochain démarrage du client. Si des modifications ne sont pas enregistrées,
   la fermeture de la fenêtre propose de les sauver.
8. **Exporter pour le jar…** : écrit un fichier `column-labels.properties` à
   poser dans `src/org/openconcerto/modules/project/` avant de reconstruire le
   jar (pour une nouvelle installation, ou pour figer les libellés d'une
   version livrée).

## 7. Ce qui est couvert à l'écran

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

## 8. Recette manuelle et vérifications exécutables

Recette cliquable pas à pas (deux comptes, retour arrière, vérification en base) :
`docs/recette-graphique-colonnes.md`.

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

## 9. Tables de sauvegarde : pourquoi un libellé peut rester sans effet

Une règle posée sur une table de **sauvegarde** (`sauvegarde_…_avant_2024`,
`…_old`, `…_copie`) est bien enregistrée, mais **n'a aucun effet visible** :
ces tables ne sont affichées dans aucune liste de l'ERP.

Elles sont reconnaissables à leur nom (préfixe `sauvegarde_`, `backup`, `copie`,
`zz_`, suffixe `_avant`, `_old`, `_ancien`, `_bck`). Au moment d'enregistrer, le
module le signale :

> ⚠ 1 règle concerne une table de sauvegarde : `sauvegarde_FACTURE_FOURNISSEUR_avant_2024`
> Ces tables n'apparaissent dans aucune liste : ces libellés n'auront aucun effet visible.

Deux façons de corriger :

- utiliser **Appliquer à toutes les tables (*)** sur la bonne colonne : la règle
  vaut pour toutes les tables, y compris la vraie `FACTURE_FOURNISSEUR` ;
- ou repérer la ligne dont la colonne **Table** vaut exactement
  `FACTURE_FOURNISSEUR` (trier la colonne Table, ou filtrer sur `facture`).

Le texte de fin d'enregistrement distingue deux choses qui n'ont rien à voir :

| Ligne du message | Signification |
|---|---|
| `1 règle en base, mode AUTO` | la modification **est** enregistrée sur le serveur (pour toute l'équipe) |
| `Listes déjà ouvertes sur ce poste : 0 colonne mise à jour` | aucune fenêtre **déjà ouverte sur ce poste** n'affiche ces colonnes ; rien à rafraîchir ici |

Un `0` sur la deuxième ligne ne veut donc pas dire que rien n'a été enregistré.

## 10. Dépannage

| Symptôme | Cause probable | Que faire |
|---|---|---|
| Le menu n'apparaît pas | l'utilisateur courant n'est pas le mieux doté | lire la ligne `[module project] menu « Libellés des colonnes » masque : …` dans la console |
| Les libellés ne changent pas | mode `OFF` en base | vérifier `PROJECT_SETTINGS` (`column.label.mode`) |
| Un poste garde les anciens noms | client pas encore redémarré | redémarrer le client (les libellés sont lus au démarrage) |
| Les tables n'existent pas | migration impossible (droits SQL) | lancer `tests/sql/migration-colonnes.sql` avec un compte administrateur de la base |
| Le libellé saisi est refusé | vide, > 128 caractères, ou caractère de contrôle | corriger la saisie ; le message indique la ligne |

Retour arrière complet : passer le mode à `OFF` (les noms techniques
réapparaissent immédiatement), ou vider la table `PROJECT_COLUMN_LABEL`.
