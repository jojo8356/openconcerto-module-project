# Correctif — « UncaughtException » à la fermeture de l'historique

## Le symptôme

En fermant la fenêtre **Historique des affaires** :

```
UncaughtException on thread Thread[#51,AWT-EventQueue-0,6,main]
Cannot invoke "org.openconcerto.sql.users.rights.JListSQLTablePanel.removeAllTableListener()"
because "this.jListePanel" is null

Caused by: java.lang.NullPointerException: … "this.jListePanel" is null
    at org.openconcerto.erp.core.reports.history.ui.ListeHistoriquePanel.removeAllTableListener(ListeHistoriquePanel.java:643)
    at org.openconcerto.modules.project.ProjectHistory$8.windowClosing(ProjectHistory.java:387)
```

La fenêtre se fermait quand même, mais une boîte d'erreur apparaissait à chaque
fois.

## La cause

`ListeHistoriquePanel` (cœur OpenConcerto) construit **d'abord** ses onglets,
puis seulement sa liste de gauche :

```java
// … boucle de construction des onglets …
this.jListePanel = new JListSQLTablePanel(req, undefinedLabel);   // ← après la boucle
```

Si la construction ne va pas jusqu'à cette ligne (table absente, onglet
impossible à filtrer, version du client où le panneau est créé plus tard),
`jListePanel` reste `null`. Or le nettoyage du cœur l'utilise sans vérifier :

```java
public void removeAllTableListener() {
    this.jListePanel.removeAllTableListener();   // NPE si null
    …
}
```

Notre module appelait cette méthode **directement** depuis l'écouteur de
fermeture de fenêtre. Une exception dans un écouteur d'événements AWT remonte au
gestionnaire global d'OpenConcerto (`Gestion.uncaughtException`), d'où la boîte
« UncaughtException ».

Le défaut qui nous revient : nous avons supposé que le panneau était toujours
prêt, et nous avons laissé l'exception s'échapper.

## Le correctif

`ProjectHistory.removeHistoryListeners()` + `HistoryPanelCleanup` :

| Point | Comportement |
|---|---|
| Vérification | réflexion sur le champ `jListePanel` : présent et non `null` ⇒ on peut nettoyer ; présent et `null` ⇒ on **n'appelle pas** le cœur |
| Versions | champ absent (autre version du client) ⇒ on appelle, l'appel est protégé |
| Robustesse | `catch Throwable` : jamais d'exception dans un écouteur de fermeture |
| Unicité | un seul nettoyage par fenêtre, même si deux écouteurs `windowClosing` sont enregistrés |
| Trace | `[module project] historique : liste de gauche non construite (jListePanel null) : nettoyage ignore` |

Conséquence pratique : la fenêtre se ferme **silencieusement**, dans tous les cas.
Les écouteurs de table restants sont sans effet visible (la fenêtre est détruite
et le ramasse-miettes récupère le panneau au prochain rafraîchissement du modèle).

## Vérifications

| Suite | Résultat |
|---|---|
| `scripts/run-tests.sh` | `AffairLinkSupportTest` **38 tests** (3 nouveaux), `ColumnLabelRulesTest` 52, `SupplierOrderToInvoiceSQLInjectorTest` 19 |
| `scripts/test-mutations-affaire.sh` | **13 contrôles, 0 échec** — la mutation 12 retire la garde et la suite échoue |
| compilation contre `OpenConcerto.jar` 1.7.6 (CI) | success |

## Recette manuelle

1. Ouvrir **Historique des affaires**.
2. Sélectionner une affaire, cliquer sur plusieurs onglets (Articles commandés,
   Factures fournisseurs, Avoirs fournisseurs…).
3. Fermer la fenêtre.
4. **Résultat attendu** : fermeture immédiate, aucune boîte « UncaughtException ».
   La console peut afficher `historique : nettoyage des ecouteurs` ou
   `… nettoyage ignore`, c'est normal dans les deux cas.
