# Module Project - Guide de developpement

**Date :** 2026-07-30

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

| Action | Commande |
| --- | --- |
| Build et packaging release | `./scripts/build-java8-compatible.sh` |
| Verification bytecode Java 8 | `scripts/verify-java8-bytecode.sh build/org.openconcerto.modules.project-1.1.jar` |
| Test fonctionnel | Verification manuelle dans OpenConcerto |

Le script de build lit la version depuis `module.properties` et produit un JAR sous `build/`.
Le JAR est compile pour Java 8 afin de rester compatible avec les environnements OpenConcerto historiques.

## Procedure de release

1. Mettre a jour `module.properties`.
2. Mettre a jour `CHANGELOG.md`.
3. Mettre a jour ou creer la fiche release dans `docs/`.
4. Executer `./scripts/build-java8-compatible.sh`.
5. Installer le JAR genere dans le repertoire modules OpenConcerto cible.
6. Redemarrer OpenConcerto et executer le scenario manuel documente dans la fiche release.

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
- Les noms de JAR doivent rester alignes avec `module.properties`; le script de build automatise cet alignement.

---

_Genere avec le workflow BMAD `document-project`._
