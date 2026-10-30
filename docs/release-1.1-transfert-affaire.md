# Module project 1.1 — l'affaire survit au transfert, et les documents existants sont réparés

**Ce jar remplace celui de `v1.1-colonne-affaire`.** Il répond à : « quand on
modifie une affaire dans une commande fournisseur et qu'on la transfère en
facture, ça ne s'affiche pas dans les factures ; même pour les existantes c'est
encore pire ».

- **Jar** : `org.openconcerto.modules.project-1.1.jar` — **287 085 octets**
  (empreinte SHA-256 dans le fichier `.sha256` joint) ;
- **téléchargement** :
  <https://github.com/jojo8356/openconcerto-module-project/releases/download/v1.1-transfert-affaire/org.openconcerto.modules.project-1.1.jar>

## La cause unique, mesurée

L'audit de **toutes** les fonctions d'affichage (5 familles, 12 tables de
documents et 12 tables de lignes — voir `docs/audit-affichage-affaire.md`) montre
qu'elles lisent toutes la même donnée : `ID_AFFAIRE` du document.

Or, dans OpenConcerto 1.7.6 :

- `grep -rn "ID_AFFAIRE" org/openconcerto/erp/injector/` → **0 occurrence** sur
  les 26 injecteurs de transfert ;
- `SQLInjector.merge()` ne copie **que** les champs déclarés ;
- donc **chaque transfert perd l'affaire** : commande → saisie d'achat (c'est le
  bouton « Transfert en facture » d'une commande fournisseur), commande → bon de
  réception, bon de réception → facture fournisseur, devis → commande,
  commande client → facture, facture → avoir…

Ce n'est ni un droit, ni un filtre, ni un problème d'affichage : la valeur n'est
jamais écrite. Pour les documents déjà créés, elle ne l'a jamais été — d'où le
« encore pire ».

## Correctif 1 — les transferts reprennent l'affaire

`AffairTransferSupport` couvre **17 paires** de transfert. Au démarrage, le
module ajoute `ID_AFFAIRE` à la liste des champs copiés **de l'injecteur déjà
enregistré par le cœur**, sans le remplacer :

- aucune règle du cœur n'est réécrite (numérotation, tables `TR_*`, transfert
  des lignes) ;
- une seule règle testée, au lieu de 17 sous-classes à maintenir ;
- idempotent, et appliqué uniquement aux paires dont les deux tables portent
  réellement la colonne.

| Sens | Paires couvertes (achats) |
|---|---|
| achats | commande → saisie d'achat, commande → bon de réception, commande → facture fournisseur, bon de réception → saisie d'achat, bon de réception → facture fournisseur, devis → commande, saisie d'achat → avoir fournisseur |
| ventes | devis → commande client, devis → facture, devis → bon de livraison, commande client → facture, commande client → bon de livraison, commande client → commande, bon de livraison → facture, facture → avoir client, facture → bon de livraison, facture → commande |

## Correctif 2 — reprise des documents existants

Menu **Aide → Reprendre les affaires des documents**. La reprise relit ce que la
base sait déjà :

1. `SAISIE_ACHAT.SOURCE` + `IDSOURCE` → affaire de la commande ou du bon de
   réception d'origine ;
2. tables de transfert `TR_COMMANDE`, `TR_BON_RECEPTION`, `TR_DEVIS`,
   `TR_COMMANDE_CLIENT`, `TR_SAISIE_VENTE_FACTURE`, `TR_SAISIE_ACHAT`,
   `TR_BON_DE_LIVRAISON` → affaire du document source ;
3. lignes → affaire de leur document (une fois celui-ci réparé).

**Garde-fous** : on ne remplit que `ID_AFFAIRE NULL` ou `= 1` (affaire
« Indéfini »), la source doit porter une vraie affaire (`> 1`), et rien n'est
écrit sans **confirmation** après affichage du nombre de documents concernés.
L'opération est rejouable à volonté.

Même travail disponible en SQL : `sql/diagnostic-affaire-transfert.sql`
(lecture seule) et `sql/reprise-affaire-transfert.sql` (dans une transaction).

## Ce que vous verrez après la mise à jour

1. Menu **Aide → Reprendre les affaires des documents** : le nombre de documents
   réparables, type par type → confirmer.
2. Rouvrir la liste des factures fournisseurs : la colonne **Affaire** se
   remplit, l'action « Historique affaire » n'est plus grisée, et les documents
   apparaissent dans l'onglet correspondant de l'historique de l'affaire.
3. Nouveau transfert d'une commande fournisseur : la facture (saisie d'achat)
   arrive **avec** l'affaire de la commande. Vérifiable en une opération.

## Preuves

| Vérification | Résultat |
|---|---|
| `AffairTransferSupportTest` | **87** vérifications |
| `AffairBackfillSupportTest` | **40** vérifications |
| `ItemAffairColumnRulesTest` | **110** vérifications |
| autres suites | 38 + 58 + 27 + 19 — toutes vertes |
| compilation | contre `OpenConcerto.jar` 1.7.6, bytecode **Java 8**, aucune erreur |

## Ce que ce jar ne fait pas

- il n'invente pas d'affaire pour un document dont la source a été supprimée
  **et** dont aucune table `TR_*` ne garde la trace : ce document reste sans
  affaire ;
- il ne modifie aucune affaire déjà renseignée ;
- il ne touche pas aux droits, ni aux affaires archivées.

Le détail de l'audit, famille d'affichage par famille d'affichage :
`docs/audit-affichage-affaire.md`.
