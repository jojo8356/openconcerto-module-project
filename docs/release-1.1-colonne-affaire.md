# Module project 1.1 — colonne **Affaire** dans le tableau des lignes

**Ce jar remplace celui de `v1.1-diagnostic-affaire`.** Il répond à la dernière
remarque : « dans le tableau je ne vois toujours pas l'affaire ».

- **Jar** : `org.openconcerto.modules.project-1.1.jar` — **270 362 octets**
  (empreinte SHA-256 dans le fichier `.sha256` joint) ;
- **téléchargement** :
  <https://github.com/jojo8356/openconcerto-module-project/releases/download/v1.1-colonne-affaire/org.openconcerto.modules.project-1.1.jar>

## Ce qui n'allait pas

Sur la capture « Détail d'une commande fournisseur » (`11870-PO-007-Avt1`) :

- le champ **Affaire** de l'en-tête est **actif et renseigné** : `11870`
  (avec la flèche du menu déroulant) ;
- le tableau des lignes affiche `Niveau, Style, Dmd Achat, Code Fourniss.,
  Famille, Code, Désignation, Descriptif, P.A.U V HT, Qté U.V., Unité de vente,
  Qté, Taxe, Poids UV net, Poids total net, Total achat HT, Total achat TTC` ;
- **aucune colonne Affaire**.

Ce n'était donc ni un problème de droits, ni un problème de données : c'est une
**fonctionnalité absente** d'OpenConcerto. Le cœur affiche l'affaire sur
l'en-tête du document et dans l'onglet « Articles commandés » de l'historique,
mais **jamais** dans le tableau des lignes du document. Rien à voir non plus avec
les 41 affaires archivées (mesure : `343 = 342 non archivées + 1 ligne
indéfinie`, l'affaire `145` / `12048` est bien dans la liste déroulante).

## Ce que fait ce jar

Une colonne **Affaire**, en **lecture seule**, est ajoutée dans les tableaux de
lignes des documents, en achat comme en vente :

| Famille | Tableaux de lignes |
|---|---|
| achats | commande fournisseur, facture fournisseur, bon de réception, demande de prix, demande d'achat, saisie d'achat, avoir fournisseur |
| ventes | commande client, facture de vente, devis, avoir client, bon de livraison |

Détails :

- elle s'affiche **juste après « Désignation »** (sinon en fin de tableau), avec
  le titre **`Affaire`** — Title Case, sans préfixe `ID_` ;
- la valeur est le **numéro saisi** de l'affaire (`11870`), jamais recasé ; à
  défaut le nom, puis `Affaire 145` ; une affaire non renseignée donne une case
  **vide** ;
- **la valeur vient de la ligne si elle porte `ID_AFFAIRE`**, sinon de son
  document parent (`COMMANDE`, `FACTURE_FOURNISSEUR`, `COMMANDE_CLIENT`...).
  C'est le cas courant en 1.7.6 : les tables de lignes n'ont pas le champ, seul
  l'en-tête l'a ;
- **lecture seule** : on ne change pas l'affaire d'une ligne dans le tableau ;
  elle se change sur le document ;
- texte en **noir** (rendu standard des colonnes texte) ;
- **aucune modification du jar OpenConcerto** : tout passe par les API publiques
  (`AbstractArticleItemTable`, `RowValuesTableModel`, `XTableColumnModel`) ;
- installation **idempotente** au moment de l'affichage : un tableau déjà équipé
  n'est jamais retouché, et une colonne qui n'aurait rien à afficher n'est pas
  créée ;
- désactivable si besoin : `-Dproject.itemAffair=false` (les lignes du journal
  disent alors pourquoi la colonne n'est pas ajoutée).

## Comment vérifier en 2 minutes

1. Fermer **complètement** le client, poser ce jar (sa taille exacte et son
   empreinte sont affichées dans la release), relancer.
2. Ouvrir une **commande fournisseur** déjà rattachée à une affaire
   (par exemple `11870-PO-007-Avt1`).
3. Dans le tableau des lignes, la colonne **Affaire** apparaît après
   **Désignation** et affiche **`11870`** sur chaque ligne.
4. Modifier la commande et changer l'affaire : la colonne suit la nouvelle
   valeur. Retirer l'affaire : la colonne se vide.

## Les tests

`ItemAffairColumnRulesTest` : **110 vérifications** (cas réel de la capture, ordre
de priorité ligne/document, affaire « indéfinie » ID 1, libellés, position de la
colonne, désactivation, liens parents de chaque tableau de lignes).

Le jar est publié après compilation contre le vrai `OpenConcerto.jar` 1.7.6 en
bytecode **Java 8**, et la CI vérifie que les deux classes de la colonne sont
bien dans l'archive.

## Ce que ce jar ne fait pas

- il ne crée **pas** de colonne `ID_AFFAIRE` sur les tables de lignes : la
  valeur est lue sur le document. Le module le fait déjà pour les en-têtes
  (`ensureAffairColumns`) ;
- il ne rend pas la colonne **modifiable** : changer l'affaire d'une ligne
  n'aurait aucun sens comptable, et le lien de la ligne vers son document est
  porté par le document lui-même ;
- il ne touche pas aux affaires archivées ni aux droits.
