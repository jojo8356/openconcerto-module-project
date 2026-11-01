# Audit complet — où l'affaire s'affiche (ou pas) pour chaque tableau

**Question posée** : « quand on modifie une affaire dans une commande fournisseur
et qu'on la transfère en facture, ça ne s'affiche pas dans les factures ; même
pour les existantes c'est encore pire ».

**Réponse** : l'affichage n'est pas le problème. L'audit des 17 fonctions
d'affichage du module (5 familles, toutes les tables) montre qu'elles lisent
toutes la même donnée — `ID_AFFAIRE` du document — et que cette donnée est
**vide après un transfert**, parce que le cœur d'OpenConcerto ne la copie jamais.

---

## 1. Ce qui a été mesuré dans le code du cœur (1.7.6)

| Mesure | Résultat |
|---|---|
| `grep -rn "ID_AFFAIRE" OpenConcerto/src/org/openconcerto/erp/injector/` | **0 occurrence** dans les 26 injecteurs de transfert |
| Injecteurs qui déclarent explicitement leurs champs (`map(...)`) | **26** : achats, ventes, avoirs, échéances |
| `SQLInjector.merge()` (l. 144-163) | ne copie **que** les champs des listes `from`/`to` |
| `SQLInjector.createDefaultMap()` (l. 256) | copie tous les champs **de même nom** — utilisé seulement quand **aucun** injecteur n'est enregistré (cas des tables de lignes) |
| `CommandeSQLElement.transfertFacture()` (l. 164-176) | ouvre une **`SAISIE_ACHAT`**, pas une `FACTURE_FOURNISSEUR` |
| `SaisieAchatSQLComponent.loadFromTable()` (l. 561-582) | `SQLInjector.getInjector(COMMANDE, SAISIE_ACHAT)` → `CommandeFactureAchatSQLInjector` |
| `CommandeFactureAchatSQLInjector` | mappe 6 champs (`ID_FOURNISSEUR`, `NOM`, `INFOS`, `NUMERO`, `T_TTC`, …) — **pas `ID_AFFAIRE`** |

**Conclusion** : le bouton « Transfert en facture » d'une commande fournisseur
crée une saisie d'achat **sans affaire**, même quand la commande en a une. Le
même mécanisme s'applique aux 16 autres paires de transfert : commande → bon de
réception, bon de réception → facture fournisseur, devis → commande, commande
client → facture, facture → avoir, etc.

Pour les documents **déjà créés** (« même les existantes »), la valeur n'a jamais
été écrite : aucune fonction d'affichage ne peut l'inventer. Il faut une
**reprise de données**.

---

## 2. Les fonctions d'affichage, une par une (aucune exception)

Toutes les tables du module sont couvertes : **12 tables de documents** et
**12 tables de lignes**.

### 2.1 Famille D1 — colonne « Affaire » des listes

- Code : `Module.setupElements()` → `elt.addListColumn(new BaseSQLTableModelColumn("Affaire", String.class))`
  (une seule fabrique, boucle sur `AffairLinkSupport.DIRECT_AFFAIR_TABLES`, `DEVIS` traité à part).
- Mécanique : `SQLElement.addListColumn` (l. 1924) range la colonne dans
  `additionalListCols` ; `SQLElement._initTableSource` (l. 1868) l'ajoute au
  modèle de liste. La valeur vient de `show_(r)` :
  `r.getForeign("ID_AFFAIRE").getString("NUMERO")`, **chaîne vide** si
  `isForeignEmpty("ID_AFFAIRE")`.
- Requête : `getPaths()` déclare `table.ID_AFFAIRE → NUMERO`, donc la valeur est
  ramenée **dans le même SELECT** (pas de requête par ligne).
- Quand elle n'affiche rien : `ID_AFFAIRE` vaut `NULL` ou `1` (indéfini).

| Table | Colonne présente | Lit | État |
|---|---|---|---|
| `COMMANDE` | oui | `COMMANDE.ID_AFFAIRE` | correct |
| `SAISIE_ACHAT` | oui | `SAISIE_ACHAT.ID_AFFAIRE` | **vide après transfert** (D6) |
| `FACTURE_FOURNISSEUR` | oui | `FACTURE_FOURNISSEUR.ID_AFFAIRE` | **vide après transfert** (D6) |
| `BON_RECEPTION` | oui | idem | **vide après transfert** |
| `AVOIR_FOURNISSEUR` | oui | idem | **vide après transfert** |
| `DEMANDE_PRIX` | oui | idem | correct |
| `COMMANDE_CLIENT` | oui | idem | correct (affaire saisie) |
| `SAISIE_VENTE_FACTURE` | oui | idem | **vide après transfert** |
| `BON_DE_LIVRAISON` | oui | idem | **vide après transfert** |
| `AVOIR_CLIENT` | oui | idem | **vide après transfert** |
| `DEVIS` | oui (colonne dédiée, avec repli sur le lien inverse) | `DEVIS.ID_AFFAIRE` puis `AFFAIRE.ID_DEVIS` | correct (l'affaire est native côté devis) |
| `DEMANDE_ACHAT_ELEMENT` | oui | `ID_AFFAIRE` | correct |

### 2.2 Famille D2 — champ « Affaire » des formulaires

- Code : `Module.setupComponents()` → `SupplierInvoiceAffairComponentSupport.register()`
  → `AffairLinkSupport.registerComponentFields()` → `ComponentsContext.putAdditionalField(table, "ID_AFFAIRE")`.
- Mécanique : le champ est ajouté au panneau supplémentaire du formulaire
  (`ComptaSQLConfElement.createAdditionalPanel`, `FormLayouter`), **modifiable**
  si l'utilisateur a le droit de modification, grisé sinon.
- Tables : les 11 tables de `DIRECT_AFFAIR_TABLES` sauf `DEVIS` (déjà natif).
- Cas d'échec : colonne absente au moment de la déclaration (le module le
  journalise et continue), ou `putAdditionalField` refusé (déjà déclaré).

### 2.3 Famille D3 — colonne « Affaire » du tableau des lignes

- Code : `ItemTableAffairColumn` (installé par `Module.start()` sur chaque
  fenêtre/composant), règles pures dans `ItemAffairColumnRules`.
- Mécanique : `RowValuesTableModel.addColumn(SQLTableElement)` (l. 146) +
  colonne d'affichage `XTableColumnModel`, insérée après « Désignation ».
  Valeur : `ID_AFFAIRE` de la ligne **sinon** celui du document parent
  (`COMMANDE`, `FACTURE_FOURNISSEUR`, `COMMANDE_CLIENT`…). Lecture seule.
- Tables : les **12** tables de lignes (`COMMANDE_ELEMENT`,
  `FACTURE_FOURNISSEUR_ELEMENT`, `BON_RECEPTION_ELEMENT`, `DEMANDE_PRIX_ELEMENT`,
  `DEMANDE_ACHAT_ELEMENT`, `SAISIE_ACHAT_ELEMENT`, `AVOIR_FOURNISSEUR_ELEMENT`,
  `COMMANDE_CLIENT_ELEMENT`, `SAISIE_VENTE_FACTURE_ELEMENT`, `DEVIS_ELEMENT`,
  `AVOIR_CLIENT_ELEMENT`, `BON_DE_LIVRAISON_ELEMENT`).
- Quand elle n'affiche rien : le document parent n'a pas d'affaire → cas de
  tous les documents transférés.

### 2.4 Famille D4 — onglets de l'historique des affaires

- Code : `ProjectHistory` + `AffairLinkSupport.planTab()` ; onglets déclarés par
  `AffairLinkSupport.getDocumentTabs()`.
- Mécanique : `ListeHistoriquePanel` filtre par
  `WHERE <table>.ID_AFFAIRE = <affaire>` (lien direct) ou via le parent pour les
  tables de lignes (`AffairLinkSupport.buildSelectionPredicate`).
- Les 12 onglets : Devis, Bons de commande, Factures, Avoirs, Bons de livraison
  clients, Demandes de prix, Bons de réception fournisseurs, Commandes
  fournisseurs, Achats, Factures fournisseurs, Avoirs fournisseurs, Demandes
  d'achat.
- Quand un document n'apparaît pas : son `ID_AFFAIRE` est vide → document
  transféré. C'est exactement le symptôme « la facture n'est pas dans
  l'historique de l'affaire ».

### 2.5 Famille D5 — action de ligne « Historique affaire »

- Code : `Module.setupElements()` → `elt.getRowActions().add(RowAction)`.
- Mécanique : `enabledFor()` renvoie faux si `isForeignEmpty("ID_AFFAIRE")` →
  sur un document transféré, **l'action est grisée**.

### 2.6 Famille D6 — les transferts (ce qui alimente D1 à D5)

- Code : 26 injecteurs du cœur + `SupplierOrderToInvoiceSQLInjector` du module.
- Mesure : **aucun** injecteur du cœur ne mappe `ID_AFFAIRE`.
- Pour les tables de lignes, le cœur fabrique un injecteur par défaut
  (`createDefaultMap`) qui copie bien `ID_AFFAIRE` — d'où l'impression que
  « l'affaire marche parfois ».

---

## 3. Tableau de synthèse : la cause est unique

| Symptôme rapporté | Famille | Cause réelle |
|---|---|---|
| la facture n'a pas d'affaire après transfert | D6 → D1/D2/D3/D4/D5 | l'injecteur ne copie pas `ID_AFFAIRE` |
| l'action « Historique affaire » est grisée sur la facture | D5 | `ID_AFFAIRE` vide |
| la facture n'apparaît pas sous l'affaire | D4 | `ID_AFFAIRE` vide |
| la colonne « Affaire » est vide dans la liste des factures | D1 | `ID_AFFAIRE` vide |
| la colonne « Affaire » est vide dans les lignes | D3 | document parent sans affaire |
| « les existantes, c'est encore pire » | données | `ID_AFFAIRE` n'a **jamais** été écrit |

Un seul point de panne, cinq conséquences visibles. Corriger l'affichage seul ne
servirait à rien : il n'y a rien à afficher.

---

## 4. La solution à tester

### 4.1 Correctif 1 — les transferts reprennent l'affaire (nouveaux documents)

`AffairTransferSupport` déclare les **17 paires** de transfert concernées. Au
démarrage, le module ajoute `ID_AFFAIRE` à la liste des champs copiés **de
l'injecteur déjà enregistré par le cœur** — sans le remplacer :

```
injector.getFrom().add(<SOURCE>.ID_AFFAIRE);
injector.getTo().add(<DEST>.ID_AFFAIRE);
```

Pourquoi cette approche plutôt qu'un sous-type par paire :

- elle ne réécrit aucune règle du cœur (numérotation, `TR_*`, transfert des
  lignes) ;
- elle couvre les 17 paires avec **une** règle testée, au lieu de 17 classes à
  maintenir ;
- elle est **idempotente** et ne s'applique qu'aux paires dont les deux tables
  portent réellement la colonne (`AffairLinkSupport.Schema`).

### 4.2 Correctif 2 — reprise des documents existants

`AffairBackfillSupport` reconstruit le lien manquant à partir de ce que la base
sait déjà, en trois étapes ordonnées :

1. `SAISIE_ACHAT` ← `COMMANDE` / `BON_RECEPTION` via `SOURCE` + `IDSOURCE` ;
2. documents ← leur source via les tables de transfert
   (`TR_COMMANDE`, `TR_BON_RECEPTION`, `TR_DEVIS`, `TR_COMMANDE_CLIENT`,
   `TR_SAISIE_VENTE_FACTURE`, `TR_SAISIE_ACHAT`, `TR_BON_DE_LIVRAISON`) ;
3. lignes ← leur document.

Garde-fous :

- on ne remplit que `ID_AFFAIRE IS NULL OR ID_AFFAIRE = 1` (**jamais** une
  affaire déjà renseignée) ;
- la source doit porter une **vraie** affaire (`> 1`) ;
- chaque reprise est conditionnée à la présence des tables et colonnes ;
- exécution **en deux temps** : comptage + confirmation, puis mise à jour.

### 4.3 Où le tester

| Quoi | Où |
|---|---|
| transfert corrigé | menu **Aide → Reprendre les affaires des documents** (comptage, puis confirmation) |
| reprise des existantes | même entrée de menu |
| mesure sans écrire | `sql/diagnostic-affaire-transfert.sql` |
| reprise en SQL | `sql/reprise-affaire-transfert.sql` |

---

## 5. Ce que cette solution ne fait pas

- elle ne devine **pas** l'affaire d'un document dont le document source est
  supprimé et dont aucune table `TR_*` ne garde la trace : ce document reste
  sans affaire, et c'est volontaire (on n'invente pas une donnée comptable) ;
- elle ne modifie pas les règles du cœur : au prochain transfert, c'est
  toujours l'injecteur du cœur qui travaille, avec un champ de plus ;
- elle n'écrase aucune affaire existante : rejouable autant de fois que voulu.

## 6. Preuves

| Vérification | Résultat |
|---|---|
| `AffairTransferSupportTest` | **87** vérifications (paires, idempotence, paires sans injecteur, sans colonne, échec isolé) |
| `AffairBackfillSupportTest` | **40** vérifications (SQL produit, jointures `TR_*` et `SOURCE/IDSOURCE`, jamais d'écrasement, ordre documents → lignes) |
| `ItemAffairColumnRulesTest` | **110** vérifications (colonne des lignes) |
| autres suites | `AffairLinkSupport` 38, `ColumnLabelRules` 58, `ProjectMenuSupport` 27, injecteurs 19 |
| compilation | `scripts/build-jar-with-curl.sh`, bytecode Java 8, contre `OpenConcerto.jar` 1.7.6 |
