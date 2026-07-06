# Module Project - Analyse de l'arbre source

**Date :** 2026-07-06

## Vue d'ensemble

Le projet est organise comme un module Java Eclipse simple. Le code applicatif est concentre sous `src/org/openconcerto/modules/project`, avec des sous-dossiers pour les elements SQL, les panels et le suivi de projet.

## Structure

```text
Module Project/
├── .classpath                         # Source Eclipse, dependance OpenConcerto, JavaSE-1.8
├── .project                           # Projet Eclipse Java
├── .settings/
│   └── org.eclipse.jdt.core.prefs     # Preferences JDT
├── module.properties                  # Identite du module OpenConcerto
├── docs/                              # Documentation BMAD generee
└── src/
    └── org/openconcerto/modules/project/
        ├── Module.java                # Point d'entree probable du module
        ├── ModuleResources.properties
        ├── ModuleResources_fr.properties
        ├── labels_fr.xml
        ├── translation_fr.xml
        ├── ProjectHistory*.java       # Ecrans/panels d'historique projet
        ├── *SQLInjector.java          # Transformations entre documents commerciaux
        ├── *Renderer.java             # Rendu de colonnes et totaux
        ├── ProjectImportExport.java   # Import/export projet
        ├── element/
        │   ├── ProjectSQLElement.java
        │   ├── ProjectStateSQLElement.java
        │   └── ProjectTypeSQLElement.java
        ├── panel/
        │   └── HistoriqueAffaireBilanPanel.java
        └── tracker/
            ├── ProjectTableModel.java
            ├── ProjectTracker.java
            └── TrackedProject.java
```

## Repertoires critiques

### `src/org/openconcerto/modules/project`

Contient le coeur du module : entree module, historique, injecteurs, renderers, import/export, ressources et traductions.

### `src/org/openconcerto/modules/project/element`

Contient les classes `SQLElement` visibles par nommage. Elles representent probablement les objets metier persistants du module : projet, etat de projet et type de projet.

### `src/org/openconcerto/modules/project/panel`

Contient au moins un panel specialise pour le bilan d'affaire.

### `src/org/openconcerto/modules/project/tracker`

Contient les classes de suivi projet et le modele de table associe.

## Points d'entree

- `src/org/openconcerto/modules/project/Module.java` : point d'entree probable du module OpenConcerto.
- `module.properties` : identite deployable du module.

## Types de fichiers

| Type | Exemples | Role |
| --- | --- | --- |
| Java | `Module.java`, `ProjectSQLElement.java` | Code applicatif |
| XML | `labels_fr.xml`, `translation_fr.xml` | Libelles et traductions |
| Properties | `ModuleResources*.properties` | Ressources module |
| Eclipse | `.project`, `.classpath` | Configuration IDE et classpath |

## Notes de developpement

Le projet depend fortement de l'environnement OpenConcerto. Les commandes de compilation ne sont pas explicites dans le depot ; le chemin de build detecte est Eclipse JDT avec sortie `bin`.

---

_Genere avec le workflow BMAD `document-project`._
