# Releases du module « project » — versions, inscription en base, publication

Ce document explique deux choses :

1. **pourquoi** OpenConcerto inscrit les modules dans la base de données, et
   quel rôle joue exactement le **numéro de version** ;
2. **comment** produire et publier une release (le jar compilé est fourni
   comme pièce jointe de la release GitHub).

---

## 1. Ce que le module déclare

Tout est dans `module.properties`, à la racine du dépôt :

```properties
id=org.openconcerto.modules.project
version=1.2
contact=ILM Informatique
```

| clé | rôle |
|---|---|
| `id` | identifiant unique du module ; **doit rester stable** dans le temps |
| `version` | version du module, format `major.minor` **en chiffres uniquement** (1.2, 2.0, 10.7…) |
| `contact` | auteur, affiché dans l'écran « Informations » |
| `depends` | (optionnel) modules requis, ex. `org.openconcerto.modules.other (1.0)` |
| `entryPoint` | (optionnel) classe d'entrée, `Module` par défaut |

Points importants :

- OpenConcerto analyse la version avec l'expression régulière
  `(\d+)(?:\.(\d+))?` : **`1.2.3` ou `1.2-SNAPSHOT` sont refusés** et font
  échouer le chargement du module.
- Il n'existe que deux niveaux : `major.minor`. Un « patch » est donc un
  incrément du numéro mineur.
- **Un numéro de version ne se réutilise jamais.** Au démarrage, OpenConcerto
  refuse un module plus ancien que celui déjà installé (message
  *« Module older than the one installed in the DB »* ou *« … locally »*).
- Notre `id` est **le même que celui du module officiel « Module Project »**
  d'OpenConcerto (`org.openconcerto.modules.project`, version 1.0). Notre jar
  est donc une **mise à jour** du module officiel : OpenConcerto le traite
  comme tel, et rejoue son installation SQL puisque 1.2 > 1.0.

---

## 2. Pourquoi le module est inscrit dans le SQL

À l'installation, OpenConcerto crée automatiquement, dans la base de **chaque
société** (schéma métier), deux tables de service :

| table | contenu |
|---|---|
| `FWK_MODULE_METADATA` | `MODULE_NAME`, `MODULE_VERSION`, `TABLE`, `FIELD`, `KEY` |
| `FWK_MODULE_DEP` | dépendances entre modules (`ID_MODULE`, `ID_MODULE_NEEDED`) |

`FWK_MODULE_METADATA` joue le rôle de **registre** :

- une **ligne par module installé** (`TABLE` et `FIELD` à `NULL`) : c'est
  l'inventaire des modules de la société ;
- une **ligne par table ou colonne créée par le module** : OpenConcerto sait
  ainsi à qui appartient chaque objet de la base, ce qui lui permet de
  supprimer proprement le module, ou de protéger ses objets ;
- la colonne **`MODULE_VERSION`** y records la version du module **au moment
  où il a créé cet objet**. Elle est stockée sous forme d'un seul entier :
  `major * 10000 + minor` (1.0 → 10000, 1.2 → 10002, 2.0 → 20000).

### Le rôle central de la version

Au démarrage, OpenConcerto compare **trois** versions :

| source | où | rôle |
|---|---|---|
| le jar sur le disque | `module.properties` du jar | la version du code |
| le poste | fichier `<dossier de configuration>/modules/<id>/version` | ce qui est installé **localement** |
| la base | `FWK_MODULE_METADATA.MODULE_VERSION` | ce qui est installé **dans cette base** |

Règles appliquées par le cœur d'OpenConcerto :

- jar **plus récent** que la base ⇒ OpenConcerto **rejoue le SQL
  d'installation** du module (la migration), puis met à jour la version
  enregistrée ;
- jar **plus ancien** que la base ou que le poste ⇒ **refus de démarrer** le
  module ;
- installer une version différente de celle de la base exige le droit
  d'administration de module (`moduleDBAdmin`) ;
- une installation qui échoue est **annulée** (transaction) et l'ancienne
  version du poste est restaurée.

En clair : **la version est le lien entre le jar sur le disque et le SQL déjà
appliqué à la base.** C'est pour cela qu'elle est stockée à deux endroits
(la base *et* le poste) et qu'elle ne doit jamais redescendre.

### Le cas de notre module

Nous ajoutons la colonne `ID_AFFAIRE` à des tables qui appartiennent à
d'autres modules (`BON_RECEPTION`, `DEMANDE_PRIX`,
`DEMANDE_ACHAT_ELEMENT`, `FACTURE_FOURNISSEUR`). Le mécanisme automatique
d'OpenConcerto ne connaît que les objets qu'il a lui-même créés : il faut donc
**déclarer** ces colonnes dans `FWK_MODULE_METADATA` — c'est ce que fait le
`INSERT` du code de `Module.setupComponents()`.

Ce `INSERT` portait un numéro de version **écrit en dur** (`10000`, soit 1.0)
alors que le module est en 1.2 : la base pouvait donc indiquer « colonne créée
par la version 1.0 » pour un module en 1.2. C'est corrigé : le numéro vient
maintenant de la version déclarée par le module
(`getFactory().getVersion().getMerged()`).

À vérifier côté base (lecture seule) :

```sql
SELECT "MODULE_NAME", "MODULE_VERSION", "TABLE", "FIELD"
FROM "FWK_MODULE_METADATA"
WHERE "MODULE_NAME" = 'org.openconcerto.modules.project'
ORDER BY "TABLE", "FIELD";
```

---

## 3. Publier une release

Le script `scripts/build-release.sh` enchaîne tout : bump de version,
compilation, tag Git, push et création de la release GitHub **avec le jar
compilé en pièce jointe**.

```sh
cd ~/openconcerto-module-project
git fetch origin
git merge --ff-only origin/arena/61954a71-openconcerto-module-project

# 1. préparer (compile seulement, rien n'est publié)
bash scripts/build-release.sh --bump patch

# 2. publier : commit + tag + push + release GitHub avec le jar
bash scripts/build-release.sh --bump patch --publish
```

Options utiles :

| option | effet |
|---|---|
| `--bump patch\|minor\|major` | incrémente la version dans `module.properties` (patch = incrément mineur) |
| `--version 1.3` | impose la version |
| `--publish` | commit, tag `v1.3`, push, release GitHub avec le jar |
| `--notes "texte"` / `--notes-file F` | notes de la release (par défaut : les commits depuis le dernier tag) |
| `--no-build` | ne compile pas (pour tester le bump seul) |
| `--no-changelog` | ne touche pas au `CHANGELOG.md` |
| `--dry-run` | affiche ce qui serait fait, ne change rien |
| `--jar /chemin/OpenConcerto.jar` | impose le jar OpenConcerto (sinon détection automatique) |

Le script refuse de publier sur `main`/`master`, refuse de réutiliser un tag
existant et n'ajoute au commit que `module.properties` et `CHANGELOG.md`
(jamais de `git add -A`).

### Ce que produit la compilation

- bytecode **Java 8** (vérifié par `scripts/verify-java8-bytecode.sh`), pour
  que le module fonctionne avec un client 1.7.6 ;
- le jar est nommé `org.openconcerto.modules.project-<version>.jar` ;
- il contient `META-INF/openConcertoModule.properties` (la copie de
  `module.properties`) — le script vérifie que la version inscrite **dans** le
  jar est bien celle attendue ;
- le résultat est copié dans `dist/` (dossier ignoré par Git).

### Procédure manuelle équivalente

```sh
# 1. version
sed -i 's/^version=.*/version=1.3/' module.properties

# 2. compilation
bash scripts/build-java8-compatible.sh
cp build/org.openconcerto.modules.project-1.3.jar dist/

# 3. commit + tag
git add module.properties CHANGELOG.md
git commit -m "Bump the module to 1.3"
git tag -a v1.3 -m "Module project 1.3"
git push origin arena/61954a71-openconcerto-module-project
git push origin v1.3

# 4. release GitHub avec le jar en pièce jointe
gh release create v1.3 --title "Module project 1.3" --notes-file notes.txt \
  dist/org.openconcerto.modules.project-1.3.jar
```

---

## 4. Checklist avant de publier

- [ ] la version de `module.properties` est **strictement supérieure** à celle
      installée (poste *et* base) ;
- [ ] le `CHANGELOG.md` décrit la nouvelle version ;
- [ ] `bash scripts/build-module-client.sh --no-install` compile sans erreur ;
- [ ] le jar produit s'installe dans le dossier `Modules` du client et le
      client démarre sans message d'erreur sur le module ;
- [ ] la fonctionnalité est testée dans l'interface graphique (voir
      `docs/test-transfert-demande-prix-interface-graphique.md`) ;
- [ ] la suite de tests passe : `bash scripts/panel-tests-docker.sh --stack ~/oc-176-docker` ;
- [ ] le rapport d'anomalies est relu :
      `bash scripts/rapport-lignes-manquantes.sh --mode docker --stack ~/oc-176-docker --out rapport-panneaux.txt`.

---

## 5. Installer une release chez le client

1. télécharger le jar de la release ;
2. le copier dans le dossier **`Modules`** lu par le client — OpenConcerto lit
   ce dossier **relativement au répertoire de lancement du client**
   (`Gestion.MODULES_DIR`), donc en pratique `/opt/openconcerto/Modules` si
   le client est lancé depuis `/opt/openconcerto` ;
3. **aligner la base** (voir ci-dessous) ;
4. **redémarrer le client** ;
5. vérifier la version dans « Informations » → « Gestion des modules ».

### 5.1 Le piège de la version épinglée en base ⚠️

Quand la version du jar change, **la base continue d'épingler l'ancienne
version**, à deux endroits :

| où | quoi |
|---|---|
| `FWK_MODULE_METADATA` (ligne « module », `TABLE` et `FIELD` à `NULL`) | version du module installé dans cette base |
| `PREF_VALUE`, nœud `modules/required` | version du module « requis » par l'administrateur |

Au démarrage, OpenConcerto exige une correspondance **exacte** entre ces
versions et un jar présent dans le dossier `Modules` du client
(`FactoriesByID.getFactories()` : `map.get(version)`, pas de « version
supérieure ou égale »). Si ça ne correspond pas, le client ne démarre pas et
affiche :

```
Impossible de configurer les modules requis
Impossible de créer les modules, not solved :
  SetMap {NO_FACTORY=[Module org.openconcerto.modules.project v1.1]}
```

C'est le « problème de métadonnées de module » qui avait fait rester
`module.properties` en `1.1` dans les versions précédentes de ce dépôt.

**La parade** : après avoir copié le nouveau jar, aligner la base sur la
version du jar :

```sh
# diagnostic (lecture seule)
bash scripts/fix-module-version.sh --mode docker --stack ~/oc-176-docker

# correction (transaction SQL, idempotente)
bash scripts/fix-module-version.sh --mode docker --stack ~/oc-176-docker --apply
```

Le script :

- lit la version installée en base et la version « modules requis » ;
- détecte la version des jars présents dans les dossiers `Modules` du poste ;
- propose la correction (`--fix`, sans écriture) ou l'applique (`--apply`) ;
- ne touche qu'aux lignes de **notre** module et laisse les autres modules
  intacts.

Une fois la base alignée, le client démarre, OpenConcerto constate que la
version du jar est plus récente que celle de la base, rejoue l'installation
SQL du module (idempotente : création de `TR_DEMANDE_PRIX` si besoin, etc.) et
met à jour les versions enregistrées.

> Si l'on préfère éviter cette manipulation en base, il faut passer par
> l'écran d'administration « Gestion des modules » du client : c'est lui qui
> écrit la version « modules requis ». Mais le client refusant de démarrer,
> cette voie n'est accessible qu'**après** avoir remis la base en état.
