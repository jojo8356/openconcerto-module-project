# Module Project - Modeles de donnees

**Date :** 2026-07-06  
**Scan :** Quick Scan

## Synthese

Aucun fichier de migration, schema SQL autonome, ORM externe ou definition de base de donnees independante n'a ete detecte.

Les modeles de donnees visibles sont des classes OpenConcerto `SQLElement` :

| Classe | Role probable |
| --- | --- |
| `ProjectSQLElement.java` | Entite projet |
| `ProjectStateSQLElement.java` | Etat de projet |
| `ProjectTypeSQLElement.java` | Type de projet |

## Relations probables

Le nommage suggere une relation entre projet, type de projet et etat de projet. Les relations exactes, cles et champs doivent etre confirmees dans le code source et/ou dans le schema OpenConcerto.

## Transformations de donnees

Les injecteurs suivants indiquent des copies ou transformations de donnees entre documents commerciaux :

- `QuoteToOrderSQLInjector.java`
- `QuoteToInvoiceSQLInjector.java`
- `OrderToInvoiceSQLInjector.java`
- `CmdToBrSQLInjector.java`

## A completer par scan profond

Pour une documentation de donnees complete, lire les sources des `SQLElement` et `SQLInjector` afin d'extraire :

- noms de tables ;
- champs affiches et obligatoires ;
- relations entre tables ;
- champs copies entre documents ;
- contraintes ou valeurs par defaut ;
- impacts des patches.

---

_Genere avec le workflow BMAD `document-project`._
