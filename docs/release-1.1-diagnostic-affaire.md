# Module project 1.1 — « Aide > Diagnostic affaire »

**Ce jar remplace celui de `v1.1-libelles-title`.** Il ajoute un diagnostic en
lecture seule qui répond, dans la session de l'utilisateur concerné, à la
question : « pourquoi le champ **Affaire** est-il vide ou grisé pour moi ? ».

## Le problème traité

Sur la base KINETIC-THERM, une commande fournisseur porte bien son affaire
(`12048-PO-001` → affaire `12048`, état « En cours »), mais le champ Affaire
s'affiche grisé chez Gisèle (`abe`) et le menu déroulant paraît vide. Les
mesures ont écarté successivement :

- les **données** : 0 pointeur cassé sur `COMMANDE` et `FACTURE_FOURNISSEUR` ;
- le **filtre société** : `AFFAIRE` n'a pas de colonne `ID_SOCIETE_COMMON`, donc
  le filtre du module ne s'applique pas ;
- l'**état des affaires** : l'affaire concernée est « En cours », pas close ;
- les **droits** : `abe` n'a pas `TABLE_ALL_RIGHTS` en propre, mais le cœur
  hérite du compte « Indéfini » (ID 1) qui l'a → `canView(AFFAIRE)` = vrai.

Reste à mesurer le dernier maillon, celui qui est visible seulement dans le
client : **le contenu réel du menu déroulant** et les droits effectifs calculés
par le cœur au moment de l'ouverture.

## Ce que fait le diagnostic

Menu **Aide → Diagnostic affaire**. Rapport affiché dans une fenêtre (texte
sélectionnable) et écrit dans le journal du client
(`[module project] diagnostic affaire`).

| Rubrique | Contenu |
|---|---|
| utilisateur | ID, nom, statut superutilisateur |
| droits | `canView` / `canModify` sur `AFFAIRE`, `COMMANDE`, `FACTURE_FOURNISSEUR`, `SAISIE_ACHAT`, `COMMANDE_CLIENT`, `SAISIE_VENTE_FACTURE` — **tels que le cœur les calcule** (héritage « Indéfini » et priorité de l'ID le plus bas déjà appliqués) |
| volumes | nombre de lignes de chaque table |
| menu déroulant | nombre d'entrées réelles, **entrées sans texte** (affaires sans état ni nom), trois premières entrées |

Aucune écriture, aucune modification de droits : uniquement des lectures. Le
calcul tourne dans un fil de fond ; aucune exception ne remonte dans l'interface.

## Comment lire le rapport

| Constat | Cause | Action |
|---|---|---|
| `lecture NON` sur `AFFAIRE` | droits | donner la lecture au compte (ou `TABLE_ALL_RIGHTS`) |
| `entrées proposées : 0` | menu déroulant vide → champ grisé | droits ou table vide |
| entrées > 0 mais l'affaire du document absente | filtre de la requête | vérifier l'état (`DOSSIER_CLOS`) |
| `entrées sans texte : N` | affaires sans état ni nom | compléter les affaires |
| tout en `oui`, entrées correctes | le problème est ailleurs | me transmettre le rapport |

## Vérifications

| Contrôle | Résultat |
|---|---|
| compilation contre `OpenConcerto.jar` 1.7.6 (bytecode Java 8) | **success** |
| `scripts/run-tests.sh` | inchangé : `ColumnLabelRulesTest` 58, `AffairLinkSupportTest` 38, `SupplierOrderToInvoiceSQLInjectorTest` 19 |
| `tests/shell/test-oc-psql.sh` | 38 contrôles, 0 échec |

Le diagnostic n'ajoute aucune règle métier : il ne lit que des API du cœur
(`UserRights.canView`, `ComboSQLRequest.getComboItems`). La correction du calcul
des droits reste couverte par `sql/diagnostic-droits-affaire.sql`.
