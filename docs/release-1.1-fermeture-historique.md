# Module project 1.1 — fermeture de l'historique sans erreur

**Ce jar remplace celui de `v1.1-listes-et-filtre`.**

## Le problème corrigé

À la fermeture de la fenêtre **Historique des affaires**, OpenConcerto affichait :

```
UncaughtException on thread Thread[#51,AWT-EventQueue-0,6,main]
Cannot invoke "JListSQLTablePanel.removeAllTableListener()" because "this.jListePanel" is null
    at ListeHistoriquePanel.removeAllTableListener(ListeHistoriquePanel.java:643)
    at org.openconcerto.modules.project.ProjectHistory$8.windowClosing(ProjectHistory.java:387)
```

Le cœur construit ses onglets **avant** la liste de gauche. Quand cette
construction ne va pas au bout, `jListePanel` reste `null`, et notre écouteur de
fermeture propageait l'exception jusque dans la boucle d'événements.

## Ce qui change

- Le nettoyage des écouteurs vérifie d'abord que le panneau est prêt
  (`HistoryPanelCleanup`), ne s'exécute qu'une fois par fenêtre, et ne peut plus
  lever d'exception (`catch Throwable`).
- La fermeture est **silencieuse** dans tous les cas. La console indique la
  décision : `historique : nettoyage des ecouteurs` ou
  `historique : liste de gauche non construite (jListePanel null) : nettoyage ignore`.
- Aucun impact sur les libellés de colonnes, le menu Paramètres ou le
  rattachement à l'affaire : mêmes fonctionnalités que le jar précédent.

## Vérifications

| Suite | Résultat |
|---|---|
| `scripts/run-tests.sh` | `AffairLinkSupportTest` **38**, `ColumnLabelRulesTest` 52, `SupplierOrderToInvoiceSQLInjectorTest` 19 |
| `scripts/test-mutations-affaire.sh` | **13 contrôles, 0 échec** (mutation 12 : garde retirée ⇒ échec) |
| compilation contre `OpenConcerto.jar` 1.7.6 (CI) | success, bytecode Java 8 |

## Recette

1. Ouvrir **Historique des affaires**, sélectionner une affaire.
2. Visiter plusieurs onglets (Articles commandés, Factures fournisseurs, Avoirs).
3. Fermer la fenêtre → fermeture immédiate, **aucune** boîte « UncaughtException ».

Analyse complète : `docs/correctif-fermeture-historique.md`.
