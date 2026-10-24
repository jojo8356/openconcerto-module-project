# Test — Commande fournisseur → Facture fournisseur : reprise de l’affaire

## Tests automatisés

Lancer depuis la racine du projet :

```sh
sh scripts/run-tests.sh
```

La classe `SupplierOrderToInvoiceSQLInjectorTest` couvre :

- le chemin de transfert `COMMANDE` → `FACTURE_FOURNISSEUR` ;
- la copie de `ID_AFFAIRE` et la conservation des champs natifs ;
- le remplacement de l’injecteur natif par l’injecteur du module ;
- le constructeur utilisant la configuration OpenConcerto ;
- les affaires `NULL` et indéfinies (`ID_AFFAIRE = 1`) ;
- l’absence de duplication du mapping après plusieurs enregistrements ;
- l’indépendance de deux transferts successifs ;
- le regroupement de commandes rattachées à la même affaire ;
- les schémas où la colonne `ID_AFFAIRE` est absente d’un côté ou des deux ;
- la non-modification de la commande source.

Ces tests utilisent des doubles de test en mémoire : ils ne nécessitent ni base
PostgreSQL ni session graphique.

## Recette manuelle dans l’interface OpenConcerto

### 1. Installer le module à tester

1. Utiliser de préférence une société/base de test.
2. Compiler le module avec l’`OpenConcerto.jar` de l’installation :

   ```sh
   OPENCONCERTO_JAR=/chemin/vers/OpenConcerto.jar sh scripts/build-java8-compatible.sh
   ```

   Le JAR produit est `build/org.openconcerto.modules.project-1.2.jar`. La
   version `1.2` correspond à celle déjà enregistrée dans la base : elle ne
   doit pas être remplacée par une version `1.1`, qui serait refusée comme trop
   ancienne au démarrage.
3. Installer le JAR généré dans le dossier `Modules` comme pour une mise à jour
   habituelle du module.
4. **Fermer puis relancer OpenConcerto.** Ce redémarrage est indispensable :
   l’injecteur de transfert est enregistré au démarrage du module.

### 2. Préparer une commande rattachée à une affaire

1. Créer ou repérer une affaire de test, par exemple `TEST-CMD-FF`.
2. Ouvrir **Gestion → Commandes fournisseurs**.
3. Créer une commande fournisseur avec :
   - le champ **Affaire** renseigné sur `TEST-CMD-FF` ;
   - un fournisseur connu ;
   - au moins une ligne d’article avec une quantité et un prix reconnaissables.
4. Enregistrer la commande et noter son numéro.

### 3. Transformer la commande en facture

1. Dans **Commandes fournisseurs**, sélectionner cette commande.
2. Faire un clic droit et choisir le transfert vers une facture fournisseur
   (le libellé peut être **Transfert vers facture fournisseur** ou, selon le
   client, **Transfert vers saisie achat**).
3. Dans le formulaire de facture qui s’ouvre, vérifier **avant l’enregistrement** :
   - **Affaire = `TEST-CMD-FF`**, automatiquement, sans le resélectionner ;
   - le fournisseur est celui de la commande ;
   - les lignes, quantités et montants sont toujours repris correctement.
4. Enregistrer la facture et noter son numéro.

### 4. Vérifier la facture enregistrée

1. Ouvrir **Factures fournisseurs**, puis la facture créée.
2. Vérifier que le champ **Affaire** est toujours `TEST-CMD-FF` après
   l’enregistrement et la réouverture.
3. Ouvrir **Historique des affaires** et sélectionner `TEST-CMD-FF` :
   - la commande apparaît dans **Commandes fournisseurs** ;
   - la nouvelle facture apparaît dans **Factures fournisseurs** ;
   - la colonne **N° commande fournisseur** de la facture contient le numéro
     noté à l’étape 2.

Le dernier point confirme dans l’interface à la fois le rattachement à
l’affaire et la conservation du lien commande → facture.

### 5. Cas de non-régression à rejouer

1. **Commande sans affaire** : créer une commande avec l’affaire indéfinie ou
   vide, la transférer et vérifier que la facture reste sans affaire. Elle ne
   doit surtout pas récupérer l’affaire du transfert précédent.
2. **Deux affaires différentes** : transférer successivement une commande de
   l’affaire A puis une commande de l’affaire B. La première facture doit rester
   sur A et la seconde doit être sur B.
3. **Champs natifs** : sur chaque facture créée, contrôler que le fournisseur,
   les articles, les quantités, les montants et le numéro de commande lié sont
   identiques au comportement avant ce changement.

### En cas d’échec

Vérifier d’abord que le nouveau JAR est bien celui chargé, que le client a été
redémarré, que la commande source affiche réellement l’affaire attendue et que
le test est fait dans la même société. Si l’affaire est reprise dans le
formulaire mais disparaît après enregistrement, noter le numéro de la facture et
le message d’erreur éventuel avant de modifier quoi que ce soit en base.
