# Recette graphique — libellés des colonnes

Test **manuel, dans l'interface**, du menu **Paramètres → Libellés des colonnes**
(jar `org.openconcerto.modules.project-1.1.jar`).

Durée : 15 minutes. Aucun SQL n'est nécessaire pour la recette ; la vérification
en base est une simple lecture (étape 6), à faire avec un compte administrateur.

Deux comptes sont nécessaires :

- **A** : le compte le mieux doté de la base (super-utilisateur, sinon
  administrateur) — c'est lui qui doit voir le menu ;
- **B** : un compte « utilisateur normal » (commercial, assistante…) — c'est lui
  qui ne doit **pas** voir le menu mais qui doit **voir les libellés changés**.

## 0. Préparation (5 min)

| # | Action | Résultat attendu |
|---|---|---|
| 0.1 | Sauvegarder la base | une sauvegarde datée existe |
| 0.2 | Fermer le client, remplacer le jar du module dans le dossier `Modules` (un seul jar de ce module), relancer | le client démarre normalement |
| 0.3 | Ouvrir la console / le log du client | aucune erreur `[module project]` autre que le compte rendu du menu |
| 0.4 | Vérifier la version du module (aide / informations) | `1.1` |

## 1. Le menu n'est proposé qu'au compte le mieux doté

| # | Action | Résultat attendu |
|---|---|---|
| 1.1 | Se connecter avec le compte **B** | accueil |
| 1.2 | Ouvrir le menu **Paramètres** | pas d'entrée **Libellés des colonnes** |
| 1.3 | Dans la console, chercher `Libellés des colonnes` | une ligne du type `… menu « Libellés des colonnes » masque : …` qui nomme le compte ayant le droit |
| 1.4 | Se déconnecter, se connecter avec **A** | accueil |
| 1.5 | Ouvrir **Paramètres** | entrée **Libellés des colonnes** présente |

> Le menu `Paramètres` apparaît à droite de `Structure`, juste avant `Aide`. Il est
> ajouté après l'ouverture de la session : compter quelques secondes (le module
> réessaie pendant 30 s) et regarder la console pour la ligne
> `menu « Libellés des colonnes » ajoute (utilisateur …)`.
>
> Si le menu est absent chez **A** aussi : lire la ligne de log (elle donne le nom
> du compte considéré comme le mieux doté) et vérifier dans **Utilisateurs** les
> cases super-utilisateur / administrateur, ainsi que les droits accordés.

## 2. L'effet par défaut, sans rien paramétrer (mode AUTO)

| # | Action | Résultat attendu |
|---|---|---|
| 2.1 | Ouvrir une liste qui contient des clés étrangères : **Achats > Commandes fournisseurs** | la liste s'ouvre |
| 2.2 | Regarder les en-têtes | plus de `ID_FOURNISSEUR` : l'en-tête s'appelle `FOURNISSEUR` |
| 2.3 | Ouvrir **Ventes > Clients** (ou toute liste avec `ID_…`) | les en-têtes `ID_CLIENT`, `ID_…` sont devenus `CLIENT`, `…` |
| 2.4 | Ouvrir l'historique du module (**Historique des affaires**) | l'onglet affaire ne montre plus `ID_AFFAIRE` mais `AFFAIRE` |
| 2.5 | Cliquer sur l'en-tête de cette colonne pour trier | le tri fonctionne, le libellé ne « saute » pas |

## 3. Choisir un libellé pour toute l'équipe

| # | Action | Résultat attendu |
|---|---|---|
| 3.1 | Se connecter avec **A**, menu **Paramètres → Libellés des colonnes** | écran avec la liste des colonnes et un champ **Filtrer** |
| 3.2 | Taper `facture` dans **Filtrer** | la liste ne garde que les lignes correspondantes |
| 3.3 | Sur la ligne `FACTURE_FOURNISSEUR` / `ID_FOURNISSEUR` (ou `*` / `ID_FOURNISSEUR`), saisir `FOURNISSEUR` dans **Libellé affiché** | la saisie reste affichée |
| 3.4 | Cliquer **Enregistrer pour l'équipe** | message de confirmation, aucune erreur en console |
| 3.5 | Rouvrir **Achats > Commandes fournisseurs** sans quitter le client | l'en-tête affiche immédiatement `FOURNISSEUR` |
| 3.6 | Saisir un libellé **vide** sur une autre ligne et enregistrer | refusé, message explicite, rien n'est enregistré |

## 4. Le réglage vaut pour les autres postes / comptes

| # | Action | Résultat attendu |
|---|---|---|
| 4.1 | Se déconnecter, se connecter avec **B** (ou fermer et relancer le client sur un autre poste) | accueil |
| 4.2 | Ouvrir **Achats > Commandes fournisseurs** | l'en-tête affiche `FOURNISSEUR` (le choix de **A**) |
| 4.3 | Ouvrir **Paramètres** | toujours pas d'entrée **Libellés des colonnes** |

> C'est le point clé du besoin : le réglage est **partagé**, il n'est pas dans les
> préférences locales du poste de **A**.

## 5. Retour arrière

| # | Action | Résultat attendu |
|---|---|---|
| 5.1 | Avec **A**, ouvrir l'écran, passer le mode à **OFF**, enregistrer | les noms techniques réapparaissent |
| 5.2 | Ouvrir une liste | les en-têtes `ID_…` sont revenus |
| 5.3 | Repasser le mode à **AUTO**, enregistrer | les libellés simplifiés reviennent (`ID_CLIENT` → `CLIENT`) |
| 5.4 | Passer à **MAPPING**, enregistrer | seules les règles saisies s'appliquent : `FOURNISSEUR` reste, les autres `ID_…` reviennent |
| 5.5 | Revenir à **AUTO** pour la suite de l'exploitation | — |

## 6. Vérification en base (lecture seule)

| # | Action | Résultat attendu |
|---|---|---|
| 6.1 | `select * from PROJECT_COLUMN_LABEL order by TABLE_NAME, COLUMN_NAME;` | les règles saisies, avec `DATE` et `ID_USER` renseignés |
| 6.2 | `select * from PROJECT_SETTINGS;` | une ligne `column.label.mode` = `AUTO` |
| 6.3 | Modifier une ligne puis `Enregistrer` à nouveau dans l'écran | pas de doublon : la ligne est remplacée (index unique table/colonne) |

## 7. Ce qu'il faut remonter en cas de problème

1. **La console du client** : toutes les lignes commençant par `[module project]`.
2. **La capture** de la liste concernée (en-têtes visibles).
3. **Le contenu des deux tables** de l'étape 6 (lecture seule).
4. Le **nom du compte** utilisé (A ou B) et ses cases super-utilisateur /
   administrateur.

## 8. Tests automatiques correspondants

```sh
sh tests/sql/e2e-colonnes.sh            # 34 controles (tables, unicite, transaction, role)
sh scripts/test-mutations-colonnes.sh   # 7 mutations : les tests savent echouer
sh scripts/run-tests.sh                 # ColumnLabelRulesTest : 39 tests
```

Ils ne remplacent pas cette recette (ils ne voient pas l'écran), mais ils
couvrent la règle de résolution, le choix du rôle, la persistance et
l'idempotence de la migration.
