# Où mettre le jar du module après téléchargement

Réponse courte : **dans le dossier `Modules` du client OpenConcerto**, le jar
directement dedans (pas de sous-dossier), et **un seul jar par module**.

```
<dossier du client OpenConcerto>/Modules/org.openconcerto.modules.project-1.1.jar
```

---

## 1. Trouver le bon dossier (30 secondes, sans chercher)

Dans le client, ouvrir le menu **? / Aide → Informations** : la fenêtre affiche
une ligne **« Dossiers des modules »** avec le ou les chemins réellement lus.
C'est la seule source fiable : selon l'installation (archive extraite,
paquet `.deb`, installeur Windows/macOS), le chemin change.

## 2. Chemins habituels

| Système | Où poser le jar |
|---|---|
| Linux, client lancé depuis `/opt/openconcerto` | `/opt/openconcerto/Modules/` |
| Linux, archive extraite dans le dossier personnel | `~/OpenConcerto-1.7.6/Modules/` (à côté de `OpenConcerto.sh`) |
| Linux, dossier de données applicatif | `~/.local/share/OpenConcerto/Modules/` |
| Windows (installeur) | `C:\Program Files\OpenConcerto\Modules\` |
| Windows (sans droits administrateur) | le chemin affiché par *Informations* |
| macOS | le dossier `Modules` de l'application, indiqué par *Informations* |

> **Le piège à connaître :** OpenConcerto lit le dossier `Modules` **relatif au
> répertoire de lancement** du client (`Gestion.MODULES_DIR = new File("Modules")`).
> Un jar posé dans un autre dossier `Modules` est **ignoré sans aucun message** :
> le module n'apparaît pas, rien ne le signale.

## 3. Installer avec le script (Linux / macOS)

```sh
# 1. voir ce que le script trouve, sans rien écrire
sh scripts/installer-jar-release.sh --liste

# 2. simulation
sh scripts/installer-jar-release.sh --jar ~/Downloads/org.openconcerto.modules.project-1.1.jar --dry-run

# 3. installation réelle
sh scripts/installer-jar-release.sh --jar ~/Downloads/org.openconcerto.modules.project-1.1.jar
```

Le script :

1. détecte tous les dossiers `Modules` du poste (et ceux du jar
   `OpenConcerto.jar` trouvé) ;
2. contrôle que le fichier **est bien un module** (`META-INF/openConcertoModule.properties`,
   bon `id`) et affiche la **version** qu'il déclare ;
3. vérifie le **bytecode Java 8** quand un JDK est disponible ;
4. **déplace l'ancien jar** du même module dans `Modules/_backup_modules/`
   puis copie le nouveau sous le nom conventionnel
   `org.openconcerto.modules.project-<version>.jar` ;
5. indique les étapes suivantes (redémarrage, vérification, cas `NO_FACTORY`).

Options : `--modules-dir DIR` (répétable), `--sans-remplacement`,
`--backup-dir DIR`, `--dry-run`, `--liste`.
Il **ne touche jamais à la base de données**.

Tests du script : `sh tests/installer/test-installer-jar.sh` (19 contrôles).

## 4. Installer à la main (tous systèmes)

1. **Sauvegarder la base** (le module ajoute des colonnes `ID_AFFAIRE`).
2. **Fermer le client.**
3. Ouvrir le dossier `Modules` (voir §1).
4. **Sortir l'ancien jar** du module (le déplacer ailleurs, ne pas le laisser à
   côté : deux versions du même module dans le dossier = comportement
   imprévisible).
5. Copier le nouveau jar :
   - Linux/macOS : `cp org.openconcerto.modules.project-1.1.jar /chemin/Modules/`
   - Windows : glisser-déposer dans l'Explorateur (accepter l'élévation si
     Windows la demande).
6. **Redémarrer le client.**
7. Vérifier : **Informations → Gestion des modules** doit lister le module en
   **1.1**.

## 5. Vérifier que c'est bien le nouveau jar qui tourne

| Où regarder | Attendu |
|---|---|
| Console / log du client au démarrage | `[module project] colonnes ID_AFFAIRE creees : [...]` (réparation, normal une fois) et **aucune** ligne `colonne ID_AFFAIRE non creee` |
| **Achats → Commandes fournisseurs** | la colonne **Affaire** existe |
| Formulaire d'une commande fournisseur | le champ **Affaire** est présent dans l'en-tête |
| **Informations → Gestion des modules** | version **1.1** |

Recette complète : [`recette-graphique-affaire-fournisseur.md`](./recette-graphique-affaire-fournisseur.md).

## 6. Si le client ne démarre plus

Message :

```
Impossible de configurer les modules requis
Impossible de créer les modules, not solved :
  SetMap {NO_FACTORY=[Module org.openconcerto.modules.project v1.1]}
```

Cause : la base épingle une **autre version** du module que celle du jar. Le
client exige une correspondance exacte.

- Remettre l'ancien jar (conservé dans `Modules/_backup_modules/`) → le client
  redémarre ;
- puis aligner la base : voir `docs/release-process.md` §5.1 et
  `scripts/fix-module-version.sh` (diagnostic en lecture seule, puis `--apply`).

## 7. Retour arrière

Remettre l'ancien jar à la place du nouveau et redémarrer. Les colonnes
`ID_AFFAIRE` ajoutées restent dans la base : elles sont inoffensives pour
l'ancienne version.
