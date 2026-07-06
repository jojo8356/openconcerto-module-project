# Module Project - Inventaire des composants

**Date :** 2026-07-06  
**Scan :** Quick Scan

## Inventaire par role

### Initialisation du module

| Fichier | Role probable |
| --- | --- |
| `Module.java` | Declaration et initialisation du module OpenConcerto |
| `module.properties` | Identite, version et contact du module |

### Elements metier SQL

| Fichier | Role probable |
| --- | --- |
| `element/ProjectSQLElement.java` | Entite projet |
| `element/ProjectStateSQLElement.java` | Entite etat de projet |
| `element/ProjectTypeSQLElement.java` | Entite type de projet |

### Historique et panels

| Fichier | Role probable |
| --- | --- |
| `ProjectHistory.java` | Composant principal d'historique projet |
| `ProjectHistoryBottomPanel.java` | Panneau inferieur generique d'historique |
| `ProjectHistoryCmdBottomPanel.java` | Panneau lie aux commandes |
| `ProjectHistoryDevisBottomPanel.java` | Panneau lie aux devis |
| `ProjectHistoryTimeBottomPanel.java` | Panneau lie au temps ou suivi temporel |
| `panel/HistoriqueAffaireBilanPanel.java` | Panel de bilan d'affaire |

### Transformations de documents

| Fichier | Role probable |
| --- | --- |
| `QuoteToOrderSQLInjector.java` | Conversion devis vers commande |
| `QuoteToInvoiceSQLInjector.java` | Conversion devis vers facture |
| `OrderToInvoiceSQLInjector.java` | Conversion commande vers facture |
| `CmdToBrSQLInjector.java` | Conversion commande vers bon associe |

### Rendu de tables

| Fichier | Role probable |
| --- | --- |
| `QuoteColumnFooterRenderer.java` | Footer de colonne devis |
| `QuoteColumnRowRenderer.java` | Ligne de colonne devis |
| `OrderColumnFooterRenderer.java` | Footer de colonne commande |
| `OrderColumnRowRenderer.java` | Ligne de colonne commande |
| `TotalHeaderRenderer.java` | Rendu d'en-tete total |

### Suivi de projet

| Fichier | Role probable |
| --- | --- |
| `tracker/ProjectTracker.java` | Logique de suivi |
| `tracker/TrackedProject.java` | Objet projet suivi |
| `tracker/ProjectTableModel.java` | Modele de table pour le suivi |

### Import/export et maintenance

| Fichier | Role probable |
| --- | --- |
| `ProjectImportExport.java` | Import/export des donnees projet |

## Ressources

| Fichier | Role |
| --- | --- |
| `ModuleResources.properties` | Ressources par defaut |
| `ModuleResources_fr.properties` | Ressources francaises |
| `labels_fr.xml` | Libelles francais |
| `translation_fr.xml` | Traductions francaises |

## Limites du scan

Les classes sont classees par nom et emplacement. Un scan profond devrait lire les sources pour confirmer les heritages, les imports OpenConcerto utilises, les points d'extension exacts et les dependances entre composants.

---

_Genere avec le workflow BMAD `document-project`._
