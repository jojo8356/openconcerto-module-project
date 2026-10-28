# Module project 1.1 — correctif de démarrage

**Ce jar remplace celui de la release `v1.1-parametres-colonnes`**, qui
empêchait le module de démarrer.

## Le problème corrigé

À l'installation du jar précédent, le client affichait au démarrage :

```
Unable to start JarModuleFactory org.openconcerto.modules.project (1.1)
Already added ID_AFFAIRE in …FactureFournisseurSQLElement…"FACTURE_FOURNISSEUR"
Caused by: java.lang.IllegalStateException: Already added ID_AFFAIRE in …
    at org.openconcerto.erp.modules.ComponentsContext.putAdditionalField(ComponentsContext.java:74)
    at org.openconcerto.modules.project.Module.setupComponents(Module.java:903)
```

Le module ne démarrait donc plus du tout : plus d'historique des affaires, plus
de menus du module, plus de rattachement à l'affaire. La cause : `ID_AFFAIRE`
était déclaré **deux fois** sur `FACTURE_FOURNISSEUR` (une fois par le support
d'origine, une fois par la boucle ajoutée avec le correctif « affaire
fournisseur »), et `ComponentsContext.putAdditionalField` lève une exception sur
un doublon.

## Ce qui change

- **une seule déclaration par table**, via
  `AffairLinkSupport.registerComponentFields` ;
- « déjà déclaré » devient une **information**, plus une erreur (cas normal au
  redémarrage, ou quand le cœur a déjà posé le champ) ;
- toute autre erreur est collectée **sans jamais interrompre le démarrage** ; le
  compte rendu est tracé :
  `[module project] affaire dans les ecrans de saisie : ajoutes […], deja presents […], refuses []` ;
- le menu **Paramètres → Affichage → Libellés des colonnes** et tout le lot
  précédent (libellés partagés pour toute l'équipe, réglages sur le serveur SQL
  et valeurs par défaut dans le jar) restent inchangés.

## Vérifications

| Suite | Résultat |
|---|---|
| `scripts/run-tests.sh` | `AffairLinkSupportTest` 35 tests, `ColumnLabelRulesTest` 39 tests, `SupplierOrderToInvoiceSQLInjectorTest` **19 tests** (2 nouveaux rejouent le plantage) |
| `scripts/test-affaire-fournisseur.sh` | **7 suites, 0 échec**, dont 12 mutations — les mutations 10 et 11 remettent l'ancien comportement et sont détectées |
| `tests/sql/e2e-colonnes.sh` | 34 contrôles, 0 échec |

Détail de l'analyse : `docs/correctif-demarrage-already-added.md`.

## Installation

1. Fermer OpenConcerto.
2. Copier `org.openconcerto.modules.project-1.1.jar` dans le dossier **Modules**
   (garder **un seul** jar de ce module ; le script
   `scripts/installer-jar-release.sh --jar …` déplace l'ancien).
3. Redémarrer le client. La console doit afficher la ligne
   `affaire dans les ecrans de saisie : …` et **plus aucune** erreur
   `Unable to start JarModuleFactory`.
4. Vérifier l'empreinte : `sha256sum org.openconcerto.modules.project-1.1.jar`
   doit correspondre au `.sha256` joint.

Aucune action en base n'est nécessaire : le plantage se produisait avant toute
écriture.

Pour construire le jar soi-même : `docs/construire-le-jar.md`.
