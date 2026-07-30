# Module Project - Synthese d'architecture publique

**Statut :** public-safe  
**Derniere verification officielle :** 2026-07-30

## Objet

Ce module etend OpenConcerto pour organiser l'activite commerciale par projet ou affaire.
Il s'aligne avec la description officielle du module "Projets et Affaires" : associer les
actions et documents a une affaire, retrouver rapidement les elements de l'ERP par affaire,
et obtenir des statistiques par affaire.

## Positionnement officiel OpenConcerto

Les pages officielles OpenConcerto verifiees indiquent :

- OpenConcerto est un ERP open source, modulaire, destine aux usages monoposte,
  multipostes et cloud.
- La version publique de telechargement affichee est OpenConcerto 1.7.6.
- Les prerequis publics indiquent Java Runtime 8 ou superieur en 64 bits.
- En multiposte, OpenConcerto requiert PostgreSQL 9 ou superieur.
- Le module "Gestion Projet" est publie comme `org.openconcerto.modules.project-1.0.jar`.

Le depot local declare le module `org.openconcerto.modules.project` en version `1.2`, mais
ne declare pas directement la version du projet OpenConcerto hote. Il reference un projet
Eclipse nomme `/OpenConcerto`; cette version doit donc etre confirmee dans l'environnement
de build effectif avant toute publication de guide d'installation.

## Comportement release 1.2

La version locale `1.2` conserve le fonctionnement general du module projets/affaires et
modifie le comportement initial de l'ecran `Historique des affaires` : le selecteur
d'affaires s'ouvre avec `Tri par nom` selectionne par defaut. Le tri par date reste
disponible explicitement depuis l'interface.

## Paradigme

Le module doit rester une extension OpenConcerto. OpenConcerto fournit le cycle de vie, les
tables, les elements SQL, les actions, les menus et l'interface Swing. Le module enregistre
ses extensions via ces points d'integration au lieu de creer un framework parallele.

Pour limiter l'accumulation de logique dans `Module.java`, les futures evolutions peuvent
extraire progressivement des services internes Java 8. Ces services doivent rester minces,
compatibles OpenConcerto, et limites aux regles metier reutilisables ou aux mutations
multi-tables.

## Invariants publics

1. `AFFAIRE` est l'agregat projet canonique du module.
2. `ID_AFFAIRE` est le lien canonique entre une affaire et les documents ERP supportes.
3. Les migrations de schema doivent etre idempotentes et tolerer les tables optionnelles.
4. Les injecteurs de documents restent minces et propagent les liens necessaires.
5. Les traitements longs ne doivent pas bloquer l'interface Swing.
6. Le code de production reste compatible Java SE 8 tant qu'aucune migration n'est decidee.
7. Les documents publics ne doivent pas contenir de chemins locaux, secrets, donnees client,
   exemples reels sensibles ou affirmations non verifiees.

## Normes Java retenues

Le projet cible Java SE 8. Les normes appliquees sont donc volontairement conservatrices :

- classes en `UpperCamelCase` ;
- methodes et champs en `lowerCamelCase` ;
- constantes immuables en `UPPER_SNAKE_CASE` ;
- pas d'imports wildcard ;
- un fichier Java par classe publique principale ;
- pas de fonctionnalites post-Java 8 dans le code de production ;
- modifications de formatage limitees au code touche.

Pour Swing, toute creation ou mutation de composant doit etre faite sur l'Event Dispatch
Thread. Les imports/exports, recalculs, scans SQL et traitements longs doivent s'executer
hors EDT, puis publier leurs resultats vers l'interface.

## Limites volontairement non publiees

Cette synthese ne publie pas :

- les chemins locaux de developpement ;
- les etats internes BMad ;
- les exemples de donnees reels ;
- les details SQL operationnels sensibles ;
- les specificites client ou societe observees dans le code ;
- les instructions de packaging client final tant que la version OpenConcerto hote et la
  chaine de deploiement cible ne sont pas confirmees.

## Sources officielles

- OpenConcerto : https://www.openconcerto.org/
- Module projets/affaires : https://www.openconcerto.org/fr/gestion-projet.html
- Telechargements et prerequis : https://www.openconcerto.org/fr/telechargement.html
- Documentation OpenConcerto : https://www.openconcerto.org/fr/documentation.html
- Specifications Java SE : https://docs.oracle.com/javase/specs/
- OpenJDK JDK 8 : https://openjdk.org/projects/jdk8/
- Oracle Swing concurrency : https://docs.oracle.com/javase/tutorial/uiswing/concurrency/
