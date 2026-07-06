# Module Project - Vue d'ensemble

**Date :** 2026-07-06  
**Type :** module applicatif Java pour OpenConcerto  
**Architecture :** module desktop/Swing monolithique integre a un ERP OpenConcerto

## Synthese

Ce projet est un module Java Eclipse nomme `Module Project`, identifie par `module.properties` comme `org.openconcerto.modules.project`. Il ajoute des fonctionnalites liees aux affaires/projets dans OpenConcerto : historique, suivi, bilans, conversion de documents commerciaux et elements SQL de reference.

Le scan effectue est un **Quick Scan** : il s'appuie sur la structure, les fichiers de configuration et les noms de fichiers. Il ne lit pas le contenu complet des sources Java. Les details de methodes, de requetes SQL et de comportements metier doivent etre confirmes par un scan profond.

## Classification

- **Type de depot :** monolithe
- **Parties detectees :** une seule partie applicative
- **Langage principal :** Java
- **Runtime cible :** JavaSE 1.8
- **IDE/build detecte :** Eclipse JDT
- **Dependance principale :** projet Eclipse `/OpenConcerto`
- **Package racine :** `org.openconcerto.modules.project`

## Pile technique

| Categorie | Technologie | Version / indice | Source |
| --- | --- | --- | --- |
| Langage | Java | JavaSE-1.8 | `.classpath` |
| Plateforme | OpenConcerto | dependance projet Eclipse `/OpenConcerto` | `.classpath` |
| IDE/build | Eclipse JDT | nature `org.eclipse.jdt.core.javanature` | `.project` |
| Module | OpenConcerto module id | `org.openconcerto.modules.project` | `module.properties` |
| Localisation | XML/properties francais | `labels_fr.xml`, `translation_fr.xml`, `ModuleResources_fr.properties` | `src/` |

## Capacites visibles

- Declaration de module via `Module.java` et `module.properties`.
- Elements SQL pour projet, type de projet et etat de projet.
- Injecteurs de transformation entre devis, commandes, bons et factures.
- Panels d'historique projet et bilan d'affaire.
- Renderers de colonnes pour devis/commandes et totaux.
- Suivi de projet via le package `tracker`.
- Import/export projet.
- Ressources et traductions francaises.

## Carte documentaire

- [Index](./index.md)
- [Architecture](./architecture.md)
- [Arbre source](./source-tree-analysis.md)
- [Inventaire des composants](./component-inventory.md)
- [Guide de developpement](./development-guide.md)
- [Contrats API](./api-contracts.md)
- [Modeles de donnees](./data-models.md)

---

_Genere avec le workflow BMAD `document-project`._
