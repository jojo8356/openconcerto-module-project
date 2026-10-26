# Audit — « je mets l'affaire sur une facture ou une commande fournisseur, et elle ne s'affiche pas »

**Date :** 2026-10-26
**Module :** `org.openconcerto.modules.project`
**Branche :** `arena/ff79607f-openconcerto-module-project`
**Portée :** rattachement à une affaire (`ID_AFFAIRE`) des documents fournisseurs —
commande fournisseur (`COMMANDE`), facture fournisseur (`FACTURE_FOURNISSEUR`),
achats (`SAISIE_ACHAT`), avoirs fournisseurs (`AVOIR_FOURNISSEUR`) et leurs lignes.

---

## 1. Résumé

Le rattachement à une affaire ne dépend pas d'un seul endroit du code, mais de
**trois couches qui doivent rester d'accord** :

| Couche | Question | Code concerné |
|---|---|---|
| Écriture | l'écran de saisie expose-t-il le champ **Affaire** ? | `Module.setupComponents` → `ComponentsContext.putAdditionalField` |
| Stockage | la colonne `ID_AFFAIRE` existe-t-elle sur la table ? | `Module.install` / `Module.setupComponents` |
| Lecture | la liste et l'historique savent-ils filtrer dessus ? | `Module.setupElements` (colonne + action), `ProjectHistory` (onglets + `fieldLink`), `ListeHistoriquePanel` (cœur OpenConcerto) |

**Un désaccord entre ces couches produit exactement le symptôme observé.** L'audit
a trouvé cinq défauts, tous corrigés ici :

| # | Défaut | Effet visible |
|---|---|---|
| **D1** | `FACTURE_FOURNISSEUR` absente de la liste `listTableAffaire` | aucune colonne « Affaire » dans la liste des factures fournisseurs, aucune action « Historique affaire », colonne jamais créée à l'installation |
| **D2** | les colonnes `ID_AFFAIRE` ne sont créées qu'à la **première** installation, et seulement pour 4 tables au démarrage | sur une base existante, `COMMANDE`, `SAISIE_ACHAT`, `AVOIR_FOURNISSEUR`… peuvent ne pas avoir la colonne : l'affaire ne peut pas être enregistrée |
| **D3** | création de colonne en **une seule instruction** `ADD COLUMN … REFERENCES` | si un document pointe vers une affaire supprimée, l'instruction échoue entièrement : **la colonne n'est jamais créée** et l'erreur est seulement imprimée dans la console |
| **D4** | onglets d'historique enregistrés **sans vérifier** qu'ils sont filtrables | une seule table sans `ID_AFFAIRE` fait lever une exception au milieu de la boucle de sélection de `ListeHistoriquePanel` : **tous les onglets suivants** restent non filtrés, donc n'affichent plus rien |
| **D5** | les tables de lignes portant leur propre `ID_AFFAIRE` sont filtrées **directement** | les lignes dont l'affaire de ligne est vide (le cas normal) disparaissent de l'historique alors que leur document est bien rattaché |

Le correctif ajoute une classe de règles testables (`AffairLinkSupport`), rend la
création des colonnes idempotente et non bloquante, et n'enregistre que des
onglets réellement filtrables.

---

## 2. Méthode d'audit

L'audit ne s'est pas arrêté à une relecture : chaque conclusion est **reproduite**
par un test exécutable.

1. **Lecture du module** (`src/org/openconcerto/modules/project/*.java`) et de
   l'historique git (commit de départ `9ddb772`).
2. **Lecture du cœur OpenConcerto** pour connaître le comportement exact de
   l'historique (`ListeHistoriquePanel`, `SQLElement`, `BaseSQLComponent`,
   `SQLSelect`, `SQLRowValuesListFetcher`, `ModuleManager`), afin de ne pas
   supposer — notamment pour l'ordre du cycle de vie des modules.
3. **Reproduction SQL** sur un vrai moteur PostgreSQL (pglite) :
   `tests/sql/e2e-affaire-fournisseur.sh` (26 contrôles).
4. **Tests unitaires** des règles de décision : `AffairLinkSupportTest`
   (35 tests) + les 16 tests existants du transfert commande → facture.
5. **Tests de mutation** : `scripts/test-mutations-affaire.sh` réintroduit
   volontairement chaque régression et vérifie que la suite la détecte
   (8 contrôles).

### Ce que fait le cœur OpenConcerto (extraits vérifiés)

`ListeHistoriquePanel` filtre **tous** ses onglets dans une seule boucle, quand
une affaire est sélectionnée :

```java
for (int i = 0; i < ListeHistoriquePanel.this.vectListePanel.size(); i++) {
    ...
    if (listFieldMap.get(table) != null) {           // lien via le document parent
        w2 = w2.and(new Where(parent.getField("ID_" + jListePanel.getModel().getTable().getName()), "=", id));
    } else if (table.equals(jListePanel.getModel().getTable())) {
        request.setWhere(new Where(table.getKey(), "=", id).and(w));
    } else {
        request.setWhere(new Where(table.getField("ID_AFFAIRE"), "=", id).and(w));   // ← D4
    }
}
```

Deux conséquences capitales :

* `table.getField("ID_AFFAIRE")` **lève** `IllegalArgumentException` si la colonne
  n'existe pas — et il n'y a aucun `try/catch` : la boucle s'arrête.
* Les onglets n'ayant pas encore reçu leur `Where` gardent celui de la
  construction de la fenêtre (aucun filtre, ou `Where.FALSE` selon la version du
  cœur) : ils n'affichent **pas** les documents de l'affaire.

Le cycle de vie des modules (vérifié dans `ModuleManager`) est :

```
install()  →  registerSQLElements() = setupElements()  →  (démarrage) setupComponents()  →  start()
```

`setupElements()` s'exécute donc **avant** `setupComponents()`, alors que c'est
`setupComponents()` qui créait `FACTURE_FOURNISSEUR.ID_AFFAIRE` : la colonne
« Affaire » et l'action « Historique affaire » des listes de l'ERP étaient
déclarées (ou non) avant que la colonne n'existe.

---

## 3. Défauts détaillés

### D1 — La facture fournisseur n'était pas dans la liste des tables à affaire

```java
// Module.java (avant)
private List<String> listTableAffaire = Arrays.asList("DEMANDE_PRIX", "BON_RECEPTION",
        "DEMANDE_ACHAT_ELEMENT", "SAISIE_VENTE_FACTURE", "AVOIR_CLIENT", "BON_DE_LIVRAISON",
        "COMMANDE_CLIENT", "DEVIS", "COMMANDE", "SAISIE_ACHAT", "AVOIR_FOURNISSEUR");
//                                            ^^^^^^^^^ FACTURE_FOURNISSEUR absente
```

Cette liste pilote **quatre** choses : la création de la colonne à
l'installation, la colonne « Affaire » des listes, l'action « Historique
affaire », et le champ supplémentaire des écrans.

Conséquence : sur une facture fournisseur, l'affaire pouvait être enregistrée
(grâce au contournement `SupplierInvoiceAffairComponentSupport` ajouté
ultérieurement) mais **restait invisible** dans la liste de l'ERP, qui n'avait
aucune colonne « Affaire ».

*Preuve indirecte* : `SupplierInvoiceAffairComponentSupport` existe uniquement
parce que la facture fournisseur avait été oubliée dans cette liste.

**Correction** : la liste devient `AffairLinkSupport.DIRECT_AFFAIR_TABLES`
(source de vérité unique), qui contient `FACTURE_FOURNISSEUR`.

### D2 — Les colonnes n'étaient créées qu'à la première installation

```java
if (ctxt.getLastInstalledVersion() == null) {   // ← une seule fois dans la vie de la base
    ...
    for (String table : this.listTableAffaire) { ... alter.addForeignColumn("ID_AFFAIRE", createTable); }
}
```

et, au démarrage, seules quatre tables étaient réparées :

```java
List<String> table2check = Arrays.asList("BON_RECEPTION", "DEMANDE_PRIX",
        "DEMANDE_ACHAT_ELEMENT", "FACTURE_FOURNISSEUR");   // ← COMMANDE absente
```

Sur une base où le module est déjà installé (restauration, nouvelle table,
colonne supprimée), `install()` n'est plus rejoué : `COMMANDE`,
`SAISIE_ACHAT`, `AVOIR_FOURNISSEUR`, `COMMANDE_CLIENT`, `SAISIE_VENTE_FACTURE`,
`AVOIR_CLIENT`, `BON_DE_LIVRAISON` pouvaient rester sans colonne. Or
l'historique **et** les écrans s'en servent : l'affaire n'était alors ni
enregistrable, ni affichable.

**Correction** : `Module.ensureAffairColumns(DBRoot)`, idempotente, appelée
depuis `install()`, `setupElements()` et `setupComponents()` — donc à chaque
démarrage du client, sur la base module **et** sur la base société.

### D3 — Un `ALTER TABLE` qui échoue en silence

```java
try {
    AlterTable alt = new AlterTable(tableCR);
    alt.addForeignColumn("ID_AFFAIRE", root.getTable("AFFAIRE"));   // ADD COLUMN ... REFERENCES
    execute(alt.asString());
} catch (SQLException e) {
    e.printStackTrace();      // ← la colonne n'existe toujours pas, et personne ne le sait
}
```

`ADD COLUMN … REFERENCES` est atomique : si la base contient **un seul**
document pointant vers une affaire supprimée (cas réel, documenté par
`docs/tests-panneaux-module-project.md`, motif `AFFAIRE INEXISTANTE`), la
contrainte est refusée et **la colonne n'est pas créée**.

**Correction** : trois étapes indépendantes (`Module.ensureAffairColumns`) :
1. `ADD COLUMN` seul — c'est lui qui rend l'affaire visible et enregistrable ;
2. contrainte `FOREIGN KEY … NOT VALID` dans un `try/catch` séparé (elle protège
   les nouvelles écritures sans bloquer sur l'historique) ;
3. métadonnées `FWK_MODULE_METADATA` + `refetchTable` pour que la colonne soit
   utilisable dans la session en cours.

Chaque échec est tracé (`[module project] …`), sans bloquer le démarrage.

### D4 — Une table non filtrable cassait **tous** les onglets suivants

`ProjectHistory` déclarait ses onglets sans vérifier que la table porte
`ID_AFFAIRE` :

```java
mapList.put("Articles commandés", Arrays.asList("COMMANDE_ELEMENT"));
if (!b.getTable("COMMANDE_ELEMENT").contains("ID_AFFAIRE")) {
    fieldLink.put(...);          // lien parent seulement si la colonne manque
}
mapList.put("Factures fournisseurs", Arrays.asList("FACTURE_FOURNISSEUR"));   // ← aucune vérification
```

Combiné à la boucle du cœur (§2), cela donne la chronologie du symptôme :
dès qu'une table de la liste n'a pas la colonne (D2/D3), l'exception survient à
cet onglet et **tous les onglets enregistrés après** ne sont plus filtrés. C'est
pourquoi une facture fournisseur ou une commande fournisseur « bien rattachée »
n'apparaît plus, alors que la valeur est correcte en base.

**Correction** : `ProjectHistory.putAffairTab(...)` demande son plan à
`AffairLinkSupport.planTab(...)` et **ignore** l'onglet quand aucun lien n'est
possible (avec un message explicite). Un onglet manquant est visible ; une
boucle cassée est silencieuse.

### D5 — Les lignes étaient filtrées sur leur propre colonne

```java
if (!b.getTable("COMMANDE_ELEMENT").contains("ID_AFFAIRE")) {   // ← la colonne existe presque toujours
    fieldLink.put(...);                                         // ← donc jamais de lien parent
}
```

Dès que la colonne existe sur la table de lignes (elle est créée par le module à
la première installation), l'historique filtre **directement** sur
`COMMANDE_ELEMENT.ID_AFFAIRE`. Or les lignes héritent normalement de l'affaire de
leur document et cette colonne de ligne est vide : les lignes disparaissent.

Reproduction (base de test, affair 330, commande 100) :

```
COMMANDE_ELEMENT : lignes des documents 330 = 4
                   visibles en filtre direct = 0        ← symptôme
                   cachées (affaire de ligne vide) = 3
filtre via le document parent        = 4              ← correctif
```

**Correction** : pour les tables de lignes suivies par le module
(`COMMANDE_ELEMENT`, `BON_RECEPTION_ELEMENT`, `AFFAIRE_TEMPS`), le filtrage
passe par le document (`preferParent`). Règle : *aucune ligne d'un document
rattaché à l'affaire n'est cachée*.

---

## 4. Ce que le correctif ne fait pas (limites assumées)

1. **Une ligne dont l'affaire diffère de celle de son document** n'apparaît plus
   sous sa propre affaire dans l'onglet « Articles commandés » : elle reste
   consultable dans la liste complète **Articles commandés** (colonne
   « Affaire ») et dans le diagnostic. Ce compromis est volontaire : le cas
   normal (affaire de ligne vide) cachait *toutes* les lignes.
2. **Les documents pointant vers une affaire supprimée** restent invisibles dans
   l'historique (comportement du cœur : la jointure sur `AFFAIRE` ne trouve
   rien). Le diagnostic les compte (`AFFAIRE INEXISTANTE`).
3. **L'onglet « Éléments de facture fournisseur »** n'est pas enregistré par
   `ProjectHistory` (il ne l'était déjà pas). Conséquence : le bilan additionne
   l'en-tête `FACTURE_FOURNISSEUR.T_HT` **et** les lignes
   `FACTURE_FOURNISSEUR_ELEMENT` quand cette liste existe ; ce point mérite une
   décision fonctionnelle et n'est pas tranché ici.
4. Le correctif ne touche pas au comportement du cœur `ListeHistoriquePanel`
   (pas de patch de classe) : il se contente de ne lui donner que des onglets
   qu'il sait filtrer.

---

## 5. Vérifications exécutées

### 5.1 Tests unitaires Java

```sh
sh scripts/run-tests.sh
```

```
AffairListSortSupportTest OK
AffairLinkSupportTest : 35 tests OK
SupplierOrderToInvoiceSQLInjectorTest OK (16 tests)
```

`AffairLinkSupportTest` couvre : couverture du module (facture + commande
fournisseur), plan de chaque onglet (direct / via parent / indisponible), absence
de table ou de colonne de liaison, prédicats SQL produits, affaire « Indéfinie »,
auto-réparation idempotente, écrans de saisie, configurations ambiguës, et la
**non-divergence** entre le Java et le script SQL de migration.

### 5.2 Test de bout en bout SQL (pglite, base réelle)

```sh
sh tests/sql/e2e-affaire-fournisseur.sh
```

26 contrôles, deux états de la même base :

```
OK   sans la colonne, l'affaire ne peut pas etre enregistree sur la commande fournisseur
OK   sans la colonne, l'onglet « Commandes fournisseurs » ne peut pas etre filtre par affaire
OK   les 12 tables de documents portent ID_AFFAIRE apres migration
OK   aucune colonne ID_AFFAIRE ajoutee sur les tables de lignes
OK   la migration est idempotente (toujours 12 colonnes)
OK   la cle etrangere vers AFFAIRE n'est pas dupliquee
OK   onglet « Commandes fournisseurs » : 1 commande pour l'affaire 330
OK   onglet « Factures fournisseurs » : la facture 200 est sous l'affaire 330
OK   colonne « Affaire » de la liste des factures fournisseurs
OK   affaire indefinie (1) : aucune commande
OK   facture pointant sur une affaire supprimee : exclue
OK   filtre via le document parent : les 4 lignes de la commande 100 remontent
Controles : 26 | echecs : 0
```

### 5.3 Tests de mutation

```sh
sh scripts/test-mutations-affaire.sh
```

```
OK  facture fournisseur oubliee : detecte
OK  lien parent sans colonne de liaison : detecte
OK  lignes filtrees directement au lieu du document : detecte
OK  derive entre le Java et le SQL de migration : detectee
OK  affaire « Indefini » acceptee : detecte
OK  colonne d affaire ajoutee sur une table de lignes : detecte
OK  migration bloquee par les affaires inexistantes : detectee
Controles : 8 | echecs : 0
```

### 5.4 Diagnostic sur la base du client (lecture seule)

```sh
sh scripts/diagnostic-affaire-fournisseur.sh --host 127.0.0.1 --port 5433 \
   --db OpenConcerto --user openconcerto --schema OpenConcerto42 --affaire 330
```

Aucune écriture. Exemple de sortie (base de démonstration) :

```
Table de lignes  | Lignes des documents 330 | Visibles (filtre direct) | CACHEES (affaire de ligne vide)
COMMANDE_ELEMENT | 4                        | 0                        | 3

================ CORRECTIONS ==============================================
1) toutes les colonnes ID_AFFAIRE existent.
2) COMMANDE_ELEMENT : 3 ligne(s) sans affaire de ligne invisibles en filtre direct.
   -> depuis ce correctif le module filtre ces lignes via COMMANDE (aucune ligne cachée).
3) les documents rattaches a une affaire supprimee restent invisibles :
   - FACTURE_FOURNISSEUR : 1 ligne(s) pointant vers une affaire inexistante
```

---

## 6. Fichiers touchés

| Fichier | Rôle |
|---|---|
| `src/org/openconcerto/modules/project/AffairLinkSupport.java` | **nouveau** — règles pures : tables à affaire, plan de filtrage d'un onglet, colonnes manquantes, champs à exposer |
| `src/org/openconcerto/modules/project/Module.java` | `FACTURE_FOURNISSEUR` dans la liste, `ensureAffairColumns` idempotente (D2/D3), garde-fou de `setupElements` (D4), champs d'écran pilotés par les règles |
| `src/org/openconcerto/modules/project/ProjectHistory.java` | onglets enregistrés via `putAffairTab` (D4), filtrage des lignes via le document (D5), action « Modifier » sur factures/achats fournisseurs |
| `tests/org/openconcerto/modules/project/AffairLinkSupportTest.java` | **nouveau** — 35 tests |
| `tests/sql/fixture-affaire-fournisseur.sql` | **nouveau** — base « installation existante » |
| `tests/sql/migration-affaire-fournisseur.sql` | **nouveau** — DDL de référence (idempotent, `NOT VALID`, index) |
| `tests/sql/e2e-affaire-fournisseur.sh` | **nouveau** — 26 contrôles de bout en bout |
| `scripts/diagnostic-affaire-fournisseur.sh` | **nouveau** — diagnostic lecture seule + mode démonstration pglite |
| `scripts/test-mutations-affaire.sh` | **nouveau** — 8 tests de mutation |
| `scripts/run-tests.sh` | exécute le nouveau test |

## 7. Procédure de recette sur une base client

1. Sauvegarder la base (le module modifie le schéma : ajout de colonnes).
2. Installer le nouveau JAR du module, puis **redémarrer le client**.
3. Vérifier dans la console de démarrage l'absence de `[module project] colonne
   ID_AFFAIRE non creee …`, puis la présence éventuelle de
   `[module project] colonnes ID_AFFAIRE creees : [...]`.
4. Ouvrir **Factures fournisseurs** : la colonne **Affaire** doit être présente
   et renseignée.
5. Ouvrir **Historique affaires**, sélectionner l'affaire : la commande et la
   facture fournisseur doivent apparaître dans leurs onglets, et leurs lignes
   dans « Articles commandés » / « Articles réceptionnés ».
6. En cas d'écart, lancer `diagnostic-affaire-fournisseur.sh` sur la base : il
   indique la colonne manquante, les lignes sans affaire de ligne et les
   documents pointant vers une affaire supprimée.
