# Correctif — « Already added ID_AFFAIRE » : le module ne démarrait plus

## Le symptôme

Au démarrage du client, avec le jar `1.1` :

```
Unable to start JarModuleFactory org.openconcerto.modules.project (1.1)
    from …/Modules/org.openconcerto.modules.project-1.1.jar

Already added ID_AFFAIRE in
org.openconcerto.erp.core.supplychain.order.element.FactureFournisseurSQLElement
"OpenConcerto"."OpenConcerto42"."FACTURE_FOURNISSEUR"

Caused by: java.lang.IllegalStateException: Already added ID_AFFAIRE in …
    at org.openconcerto.erp.modules.ComponentsContext.putAdditionalField(ComponentsContext.java:74)
    at org.openconcerto.modules.project.Module.setupComponents(Module.java:903)
```

Conséquence : **le module entier refuse de démarrer** (pas d'historique des
affaires, pas de menu, pas de rattachement). Le client, lui, continue de
fonctionner sans le module.

## La cause

`ComponentsContext.putAdditionalField` **lève une exception** quand le champ
supplémentaire est déjà déclaré pour l'élément :

```java
public final void putAdditionalField(final String tableName, final String name) {
    final SQLElement elem = checkField(tableName, name);
    if (elem.putAdditionalField(name)) {
        this.fields.add(elem, name);
    } else {
        throw new IllegalStateException("Already added " + name + " in " + elem);
    }
}
```

Or le module déclarait l'affaire sur la facture fournisseur **deux fois** :

1. `SupplierInvoiceAffairComponentSupport.register(ctxt)` (correctif d'origine,
   une seule table) ;
2. la boucle ajoutée avec le correctif « affaire sur les documents
   fournisseurs », qui parcourt `AffairLinkSupport.DIRECT_AFFAIR_TABLES` — liste
   dans laquelle `FACTURE_FOURNISSEUR` a justement été ajoutée.

La première déclaration passe, la seconde lève `IllegalStateException`… en
plein `setupComponents`, donc pendant le démarrage du module. Ce n'était pas un
défaut d'affichage : c'était un **crash au démarrage**, présent depuis le lot
« affaire fournisseur » et découvert à l'installation du jar.

## Le correctif

Un seul point d'entrée, `AffairLinkSupport.registerComponentFields(schema, cible)` :

- **une seule déclaration par table** (ensemble de tables déjà traitées) ;
- `IllegalStateException` = « déjà déclaré » → comptée comme une information,
  **pas** comme une erreur (cas normal : cœur, autre module, redémarrage) ;
- toute autre erreur (champ non créé par le module, table sans élément) est
  collectée par table et **n'empêche jamais le démarrage** ;
- le compte rendu est tracé au démarrage :
  `affaire dans les ecrans de saisie : ajoutes […], deja presents […], refuses […]`.

`SupplierInvoiceAffairComponentSupport.register(ctxt, schema)` n'est plus qu'un
adaptateur vers `ComponentsContext` : il ne décide plus rien, donc il ne peut
plus déclarer deux fois. `Module.setupComponents` l'appelle une fois, sous
`try/catch`.

## Vérifications

| Test | Ce qu'il prouve |
|---|---|
| `SupplierOrderToInvoiceSQLInjectorTest` (19 tests) | le double de test de `ComponentsContext` **lève comme le vrai** sur un doublon ; `testModuleStartupSurvivesAlreadyDeclaredField` rejoue le scénario exact du plantage (deux appels) et vérifie qu'il ne lève plus et qu'aucune table n'est déclarée deux fois |
| `testAffairFieldDeclaredOncePerTable` | une déclaration par table, même quand plusieurs documents la concernent |
| `testModuleStartupSurvivesFieldNotCreatedByModule` | une table refusée n'empêche pas les autres d'être déclarées |
| mutations 10 et 11 de `scripts/test-mutations-affaire.sh` | en remettant l'ancien comportement (relancer l'exception, ou supprimer le dédoublonnage), la suite **échoue** — les tests protègent bien ce point |

```sh
sh scripts/run-tests.sh                 # 19 tests OK
sh scripts/test-affaire-fournisseur.sh  # 7 suites, 0 échec (dont 12 mutations)
```

## Ce qu'il faut faire sur un poste déjà planté

1. Fermer OpenConcerto.
2. Remplacer le jar dans le dossier **Modules** par un jar ≥
   `v1.1-demarrage-corrige` (un seul jar de ce module).
3. Redémarrer. La console doit afficher une ligne du type
   `[module project] affaire dans les ecrans de saisie : ajoutes […], deja presents […], refuses []`
   et **plus aucune** `Unable to start JarModuleFactory`.

Aucune action en base n'est nécessaire : le plantage se produisait avant toute
écriture, rien n'a été laissé à moitié fait.
