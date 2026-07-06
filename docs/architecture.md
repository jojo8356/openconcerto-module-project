# Module Project - Architecture

**Date :** 2026-07-06  
**Scan :** Quick Scan

## Resume

`Module Project` est un module Java pour OpenConcerto. L'architecture visible est monolithique et orientee extension d'une application desktop ERP : le module declare des ressources, des elements SQL, des panels Swing/OpenConcerto, des renderers de table et des injecteurs de conversion entre documents commerciaux.

## Style architectural

- **Module applicatif integre :** le projet ne porte pas son propre serveur, runtime ou packaging autonome visible.
- **Extension OpenConcerto :** la dependance `/OpenConcerto` dans `.classpath` indique que les APIs centrales viennent du projet OpenConcerto parent.
- **Couche UI desktop :** presence de `Panel`, `Renderer`, `TableModel` et classes d'historique.
- **Couche metier/persistence OpenConcerto :** presence de `SQLElement` et `SQLInjector`.
- **Ressources localisees :** XML/properties francais.

## Composants principaux

| Zone | Fichiers | Responsabilite probable |
| --- | --- | --- |
| Module | `Module.java`, `module.properties` | Declaration, initialisation et integration OpenConcerto |
| Elements SQL | `element/*SQLElement.java` | Definition des entites metier persistantes |
| Transformations | `*SQLInjector.java` | Conversion/copie de donnees entre devis, commandes, bons et factures |
| Historique projet | `ProjectHistory*.java`, `HistoriqueAffaireBilanPanel.java` | Presentation et synthese historique des affaires/projets |
| Rendu UI | `*Renderer.java`, `TotalHeaderRenderer.java` | Affichage specialise dans les tables |
| Suivi | `tracker/*` | Modele et logique de suivi de projet |
| Localisation | `labels_fr.xml`, `translation_fr.xml`, `ModuleResources_fr.properties` | Textes et libelles francais |

## Flux d'integration visibles

Les noms de classes indiquent des flux entre documents commerciaux :

- Devis vers commande : `QuoteToOrderSQLInjector`
- Devis vers facture : `QuoteToInvoiceSQLInjector`
- Commande vers facture : `OrderToInvoiceSQLInjector`
- Commande vers bon de reception/livraison selon convention OpenConcerto : `CmdToBrSQLInjector`

Les details de champs copies et de regles metier ne sont pas etablis par ce scan rapide.

## Donnees

Les entites visibles sont :

- `ProjectSQLElement`
- `ProjectStateSQLElement`
- `ProjectTypeSQLElement`

La structure exacte des tables, champs et contraintes doit etre confirmee par lecture des sources et/ou du schema OpenConcerto.

## Tests

Aucun fichier de test n'a ete detecte dans ce depot pendant le scan rapide.

## Deploiement

Aucune configuration de deploiement autonome n'a ete detectee. Le module semble destine a etre compile/deploye dans l'ecosysteme OpenConcerto, probablement via Eclipse ou un outillage externe non present dans ce depot.

## Risques et contraintes

- Le depot ne contient pas de script de build autonome.
- La dependance `/OpenConcerto` doit etre disponible dans l'espace de travail Eclipse.
- Le scan rapide n'a pas valide les signatures, heritages ni imports des classes Java.
- Les regles metier reelles des injecteurs et panels doivent etre documentees par un scan profond.

---

_Genere avec le workflow BMAD `document-project`._
