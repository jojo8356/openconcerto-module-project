# Module Project - Guide de developpement

**Date :** 2026-07-06

## Prerequis

- Eclipse avec support Java/JDT.
- JDK compatible JavaSE 1.8.
- Projet OpenConcerto disponible dans le meme workspace Eclipse sous le nom `/OpenConcerto`.

## Configuration detectee

Le fichier `.classpath` declare :

- `src` comme repertoire source.
- `/OpenConcerto` comme dependance projet.
- `JavaSE-1.8` comme environnement Java.
- `bin` comme repertoire de sortie.

Le fichier `.project` declare la nature Java Eclipse `org.eclipse.jdt.core.javanature`.

## Installation locale

1. Importer ce dossier comme projet Java Eclipse existant.
2. Importer ou creer le projet OpenConcerto attendu par la reference `/OpenConcerto`.
3. Verifier que le JRE System Library pointe vers JavaSE 1.8.
4. Laisser Eclipse compiler vers `bin`.

## Commandes

Aucune commande CLI de build/test n'a ete detectee dans le depot.

| Action | Commande |
| --- | --- |
| Build | Via Eclipse JDT |
| Test | Aucun script detecte |
| Packaging | Non documente dans le depot |

## Conventions visibles

- Package racine : `org.openconcerto.modules.project`.
- Nommage francais/anglais mixte, coherent avec OpenConcerto : `HistoriqueAffaireBilanPanel`, `QuoteToOrderSQLInjector`.
- Ressources francaises separees dans `*_fr.*`.
- Entites metier suffixees `SQLElement`.
- Transformations suffixees `SQLInjector`.
- Composants UI suffixes `Panel`, `Renderer`, `TableModel`.

## Tests

Aucun fichier de test n'a ete trouve. Avant une evolution fonctionnelle, prevoir au minimum :

- tests de transformation pour les injecteurs SQL ;
- tests ou scenarios manuels pour les panels d'historique ;
- verification dans un environnement OpenConcerto avec donnees de devis, commandes et factures.

## Points d'attention

- Les changements doivent etre verifies dans l'application OpenConcerto, pas seulement par compilation du module.
- Les schemas et noms de tables peuvent dependre du projet OpenConcerto parent.
- Les ressources de traduction doivent rester synchronisees avec les libelles UI.

---

_Genere avec le workflow BMAD `document-project`._
