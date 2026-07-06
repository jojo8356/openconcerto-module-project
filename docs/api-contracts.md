# Module Project - Contrats API

**Date :** 2026-07-06  
**Scan :** Quick Scan

## Synthese

Aucun serveur HTTP, route REST, GraphQL, gRPC ou contrat API externe n'a ete detecte dans la structure du depot.

Ce projet semble etre un module Java desktop integre a OpenConcerto, avec des interactions via classes Java, elements SQL et composants UI plutot que via API reseau.

## Interfaces internes visibles

Les interfaces internes probables sont :

- points d'extension OpenConcerto dans `Module.java` ;
- elements SQL dans `element/*SQLElement.java` ;
- injecteurs de donnees dans `*SQLInjector.java` ;
- composants UI Swing/OpenConcerto dans `*Panel.java`, `*Renderer.java`, `ProjectTableModel.java`.

## A completer par scan profond

Un scan profond doit confirmer :

- les classes parentes et interfaces implementees ;
- les methodes exposees par `Module.java` ;
- les methodes surchargees des `SQLElement` et `SQLInjector` ;
- les contrats implicites avec les tables OpenConcerto.

---

_Genere avec le workflow BMAD `document-project`._
