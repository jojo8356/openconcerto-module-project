# Transfert « demande de prix » → « commande fournisseur »

Fonctionnalité ajoutée au module **project** : depuis l'onglet « Demandes de
prix » de l'historique des affaires, un bouton **« Transfert en commande
fournisseur »** transforme la demande de prix sélectionnée en commande
fournisseur (lignes recopiées, prix restant à saisir).

## Ce qui a été fait

### 1. Deux injecteurs de transfert (mécanisme standard OpenConcerto)

| Fichier | Rôle |
|---|---|
| `src/org/openconcerto/modules/project/DemandePrixCommandeSQLInjector.java` | En-tête : `DEMANDE_PRIX` → `COMMANDE`, avec `storeTransfer = true` (le lien source/destination est mémorisé). Recopie aussi `ID_AFFAIRE`, `ID_FOURNISSEUR`, `DATE` et `NOM` **si les colonnes existent des deux côtés**. |
| `src/org/openconcerto/modules/project/DemandePrixElementCommandeElementSQLInjector.java` | Lignes : `DEMANDE_PRIX_ELEMENT` → `COMMANDE_ELEMENT`. Recopie les colonnes de même nom, mappe `DESIGNATION` vers `DESCRIPTIF`/`DESIGNIF` si besoin, et **ne recopie pas les totaux** (`T_HT`, `T_TTC`, `T_PA_HT`, `T_PA_TTC`, `MONTANT_HT`, `MONTANT_TTC`) : le prix reste à saisir. |

### 2. La table de transfert est créée par OpenConcerto, pas à la main

`Module.install()` et `Module.setupComponents()` appellent
`SQLInjector.createTransferTables(root)` : OpenConcerto crée tout seul
`TR_DEMANDE_PRIX` (colonne `ID_DEMANDE_PRIX` + clé étrangère `ID_COMMANDE`).
**Aucune commande SQL manuelle n'est nécessaire**, et l'opération est
idempotente (elle ne refait rien si la table existe déjà).

### 3. Le bouton

`src/org/openconcerto/modules/project/TransfertDemandePrixAction.java` ajoute
une `RowAction` (« Transfert en commande fournisseur ») à l'élément
`DEMANDE_PRIX`, uniquement si la table des lignes existe. L'action :

1. ouvre le formulaire **standard** d'une commande fournisseur via
   `TransfertBaseSQLComponent.openTransfertFrame(...)` (l'en-tête est
   pré-rempli par l'injecteur) ;
2. charge les lignes avec
   `loadItem(commande.getRowValuesTablePanel(), eltDemandePrix, id, eltLignes)`.

À l'enregistrement de la commande, `SQLInjector.commitTransfert(...)` écrit le
lien dans `TR_DEMANDE_PRIX` : la commande reste donc rattachée à la demande de
prix d'origine.

## Construction du module (à faire sur le poste qui a le JDK)

Le code est en Java 8 (compatible OpenConcerto 1.7.6).

```sh
cd ~/openconcerto-module-project
git fetch origin
git merge --ff-only origin/arena/61954a71-openconcerto-module-project
```

Compiler le jar du module :

```sh
OPENCONCERTO_JAR="$HOME/OpenConcerto-1.7.6-multiposte/OpenConcerto.jar" \
  sh scripts/build-java8-compatible.sh
```

Le script produit `build/org.openconcerto.modules.project-1.1.jar` et vérifie
que le bytecode est bien Java 8 (major ≤ 52).

Si le jar d'OpenConcerto n'est pas à cet endroit :

```sh
ls "$HOME/OpenConcerto-1.7.6-multiposte"/*.jar
```

## Installation dans le client

```sh
mkdir -p "$HOME/OpenConcerto-1.7.6-multiposte/Modules"
cp build/org.openconcerto.modules.project-1.1.jar "$HOME/OpenConcerto-1.7.6-multiposte/Modules/"
```

Puis redémarrer le client OpenConcerto.

> Si le module est installé via le menu d'administration du client
> (« Mise à jour des modules »), c'est ce menu qu'il faut utiliser ; le jar
> ci-dessus est la méthode directe, utile pour un test rapide.

## Test fonctionnel

1. Ouvrir une affaire.
2. Onglet « Demandes de prix » : sélectionner **une seule** demande de prix
   (le bouton est désactivé sur une sélection multiple).
3. Cliquer sur « Transfert en commande fournisseur ».
4. Vérifier que :
   - l'en-tête de la commande est rempli (fournisseur, affaire, date) ;
   - les lignes sont recopiées (désignation, quantité, unité) ;
   - les prix unitaires et les totaux sont **vides** (à saisir).
5. Saisir un prix, enregistrer la commande.
6. Vérifier dans la base que le lien existe :

```sql
SELECT * FROM "TR_DEMANDE_PRIX";
```

## Points de vigilance

- Le module **supplychain** (qui fournit les tables `DEMANDE_PRIX`,
  `DEMANDE_PRIX_ELEMENT`) doit être présent, sinon le bouton n'apparaît pas
  (le code le détecte et ne fait rien).
- Le tableau `COMMANDE_ELEMENT` doit exister (il est créé par le module
  supplychain).
- La commande créée est une vraie commande : elle compte dans le bilan et
  dans les « à réceptionner ».
- Le bouton n'apparaît que si l'élément `DEMANDE_PRIX` est connu du client
  (il est ajouté à l'installation du module, donc après un redémarrage).
