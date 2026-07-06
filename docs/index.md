# Module Project Documentation Index

**Type :** monolithe module Java/OpenConcerto  
**Langage principal :** Java  
**Architecture :** module desktop/Swing integre a OpenConcerto  
**Derniere mise a jour :** 2026-07-06

## Vue d'ensemble

Ce projet contient un module OpenConcerto identifie par `org.openconcerto.modules.project`. Il apporte des fonctionnalites de gestion de projets/affaires : historique, suivi, bilans, elements SQL, rendus UI et transformations entre documents commerciaux.

Le scan courant est un **Quick Scan**. Il fournit une cartographie exploitable pour l'assistance IA, mais les details internes des classes Java doivent etre confirmes par un scan profond avant une evolution metier complexe.

## Reference rapide

- **Stack :** JavaSE 1.8, Eclipse JDT, OpenConcerto
- **Point d'entree probable :** `src/org/openconcerto/modules/project/Module.java`
- **Module id :** `org.openconcerto.modules.project`
- **Dependance principale :** projet Eclipse `/OpenConcerto`
- **Source root :** `src/`
- **Sortie build :** `bin/`

## Documentation generee

- [Vue d'ensemble](./project-overview.md)
- [Architecture](./architecture.md)
- [Analyse de l'arbre source](./source-tree-analysis.md)
- [Inventaire des composants](./component-inventory.md)
- [Guide de developpement](./development-guide.md)
- [Contrats API](./api-contracts.md)
- [Modeles de donnees](./data-models.md)
- [Synthese d'architecture publique](./public-architecture-summary.md)

## Documentation existante

Aucune documentation existante n'a ete detectee avant generation dans `docs/`.

## Demarrage

1. Importer le projet dans Eclipse comme projet Java existant.
2. Verifier que le projet OpenConcerto est disponible dans le workspace sous `/OpenConcerto`.
3. Utiliser JavaSE 1.8.
4. Compiler via Eclipse JDT.
5. Tester le module dans une instance OpenConcerto representative.

## Pour le developpement assiste par IA

Pour une petite correction ciblee, fournir cet index comme contexte puis pointer vers le fichier concerne dans `src/org/openconcerto/modules/project`.

Pour une evolution fonctionnelle :

- lire [Architecture](./architecture.md) pour les contraintes ;
- lire [Inventaire des composants](./component-inventory.md) pour identifier les classes candidates ;
- lire [Modeles de donnees](./data-models.md) avant toute modification SQL ;
- effectuer un scan profond ou une lecture source ciblee avant de modifier les injecteurs et `SQLElement`.

## Limites connues

- Le contenu des fichiers Java n'a pas ete lu en entier pendant ce Quick Scan.
- Aucun test automatise n'a ete detecte.
- Aucun script de build autonome n'a ete detecte.
- La documentation des champs SQL et des regles metier reste a confirmer dans les sources.

---

_Documentation generee par le workflow BMAD `document-project`._
