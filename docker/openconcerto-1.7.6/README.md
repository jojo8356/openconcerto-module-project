# Stack Docker pour OpenConcerto 1.7.6

> **Variante Podman** : une pile identique, sans Docker, se trouve dans
> [`podman/openconcerto-1.7.6/`](../../podman/openconcerto-1.7.6/README.md),
> avec le script `scripts/podman-openconcerto.sh` (`up`, `down`, `status`,
> `logs`, `copy`, `client`, `sql`, `diagnose`).

PostgreSQL 17 + Adminer, pour faire tourner une base OpenConcerto 1.7.6 en
conteneur. Le client OpenConcerto reste installé sur l'hôte : en multiposte,
les clients se connectent directement à PostgreSQL, il n'y a pas de serveur
d'application à conteneuriser.

## 0. Prérequis

- Docker + compose v2 (`docker compose version`)
- Les ports `5433` et `8082` libres sur `127.0.0.1` — le `5432` est volontairement
  évité, le cluster natif l'occupe déjà.
- Un dump OpenConcerto 1.7.6 au format `pg_dump -Fc`, placé dans `./dumps/`

## 1. Démarrage

```sh
cp .env.example .env      # puis éditer POSTGRES_PASSWORD
mkdir -p dumps            # y déposer le dump .dumpsql
docker compose up -d
docker compose ps         # db doit passer à healthy
```

## 2. Collation française (si la base source est en fr_FR.UTF-8)

Sur la base d'origine :

```sh
sudo -u postgres psql -d OpenConcertoKineticTherm -Atc \
  "select datcollate, datctype, pg_encoding_to_char(encoding) \
     from pg_database where datname='OpenConcertoKineticTherm'"
```

Si la réponse est `fr_FR.UTF-8|fr_FR.UTF-8|UTF8`, démarrer la stack avec le
fichier d'override :

```sh
docker compose -f docker-compose.yml -f docker-compose.fr_FR.yml up -d --build
docker compose exec db psql -U openconcerto -d postgres -Atc \
  "select datcollate, datctype from pg_database where datname='postgres'"
```

La seconde commande doit répondre `fr_FR.UTF-8|fr_FR.UTF-8` ; à partir de là,
`CREATE DATABASE … LC_COLLATE 'fr_FR.UTF-8'` est accepté.

### Pourquoi un override et pas un `localedef` dans le conteneur

Générer la locale dans un conteneur **déjà démarré** ne suffit pas. Observé en
conditions réelles : `locale -a` liste `fr_FR.utf8`, `LC_ALL=fr_FR.UTF-8 locale
charmap` répond `UTF-8` avec un code de retour 0, et `CREATE DATABASE …
LC_COLLATE 'fr_FR.UTF-8'` échoue malgré tout sur `invalid LC_COLLATE locale
name`. Le postmaster a été lancé avant la génération de la locale et ne la voit
pas. La locale doit donc exister dans l'image, avant le premier `initdb` :
c'est le rôle du `Dockerfile`.

La collation par défaut du cluster est figée à l'`initdb` : ajouter l'override
sur un volume existant ne change rien, il faut repartir d'un volume vierge
(`docker compose down -v`, ce qui perd les données du conteneur).

## 3. Restaurer le dump 1.7.6

Le plus simple est le script qui enchaîne tout — dump de la base native,
restauration dans le conteneur, correctif multi-schémas, puis contrôle de la
colonne et du nombre de tables par schéma des deux côtés :

```sh
scripts/copy-openconcerto-db-to-docker.sh -n    # plan détaillé, ne modifie rien
scripts/copy-openconcerto-db-to-docker.sh       # exécute, avec confirmation
```

Il retrouve ses deux scripts voisins dans son propre dossier, et lit le mot de
passe du conteneur dans `PGPASSWORD` ou dans `POSTGRES_PASSWORD` du `.env`.

Pour restaurer manuellement un dump déjà présent, avec le script du dépôt et en
visant le port publié :

```sh
PGPASSWORD=... ./scripts/restore-openconcerto-dump.sh \
  -f docker/openconcerto-1.7.6/dumps/<ton-dump>.dumpsql \
  -d OpenConcerto -U openconcerto -h 127.0.0.1 -p 5433 -y
```

Attention : ce script **supprime** la base cible avant de la recréer
(`dropdb`, puis `createdb`, puis `pg_restore`). Sur une stack neuve c'est sans
conséquence ; ne jamais le pointer vers la base de production.

Si la locale du dump n'existe pas dans le conteneur, relancer avec
`LOCALE=C.UTF-8`.

## 4. Brancher le client 1.7.6

Le client lit sa configuration dans `~/.config/OpenConcerto/main.properties`.

**L'assistant graphique ne peut pas faire leswitch.** Dans `ServerFinderPanel`
le champ « Base de données » est en lecture seule (`textBase.setEditable(false)`,
rempli depuis la propriété `systemRoot` existante puis réinjecté tel quel), et
l'onglet n'expose aucun champ identifiant / mot de passe. Il n'y a donc pas
d'interface pour changer de base ni pour saisir des identifiants.

C'est pourquoi la bascule se fait par le script suivant, qui réécrit le
`main.properties` (sauvegarde automatique à côté), aligne le mot de passe du
rôle SQL du conteneur et contrôle la connexion :

```sh
scripts/switch-openconcerto-client-db.sh -t docker -r -n   # plan, ne modifie rien
scripts/switch-openconcerto-client-db.sh -t docker -r      # exécute, avec confirmation
scripts/switch-openconcerto-client-db.sh -t native          # retour à la base native
```

Ce qu'il écrit :

```properties
server.ip=127.0.0.1\:5433
systemRoot=OpenConcerto
server.driver=postgresql
server.login=openconcerto
server.password=openconcerto
```

Deux points qui ne se devinent pas :

- **Les identifiants par défaut d'OpenConcerto sont `openconcerto` /
  `openconcerto`** (`ComptaPropsConfiguration` les applique quand le fichier de
  configuration n'en contient pas, et `ServerFinderConfig` — le bouton
  « Tester la connexion » de l'assistant — les utilise toujours). Le rôle du
  conteneur doit donc porter ce mot de passe : c'est le rôle de l'option `-r`,
  qui fait un `ALTER ROLE` dans le conteneur et met le `.env` en cohérence.
  Avec `-r`, le bouton « Tester la connexion » de l'assistant fonctionne
  également sur le conteneur.
- **`server.ip` contient l'hôte et le port dans une seule valeur**, le deux-points
  échappé (`\:`) : c'est le format qu'écrit OpenConcerto, il faut le
  respecter. `127.0.0.1` et non `localhost`, qui peut résoudre en `::1` alors
  que le conteneur n'écoute que sur `127.0.0.1`.

Vérifier ensuite dans le log de démarrage la ligne `Ip:127.0.0.1:5433` — c'est
elle qui dit à quelle base le client parle.

## 5. Contrôler les droits d'un utilisateur

Les droits OpenConcerto vivent en base, dans `USER_RIGHT` (un couple
`CODE` / `OBJECT` par ligne, plus un `HAVE_RIGHT`). La règle de résolution
d'OC (`UserRightsManager.expand()`) est **la ligne d'ID le plus bas l'emporte**
pour un couple donné : une autorisation ajoutée plus tard sur un couple déjà
présent est **ignorée**. C'est ce qui donne l'impression, dans l'interface,
que le droit a été accordé alors qu'il ne l'est pas.

Le script compare deux comptes et applique, si besoin, un correctif SQL :

```sh
scripts/test-droits-utilisateur.sh -1 yves -2 gisele          # rapport
scripts/test-droits-utilisateur.sh -1 yves -2 gisele -f -n    # correctif (plan)
scripts/test-droits-utilisateur.sh -1 yves -2 gisele -f       # correctif (appliqué)
```

Il affiche les droits bruts, les droits effectifs, le différentiel, les droits
sur les tables du transfert, l'accès aux sociétés, puis génère le SQL
(`UPDATE` de la ligne effective + suppression des lignes masquées) avec un
script de restauration. **Aucun rechargement de la base n'est nécessaire** :
c'est un `UPDATE`/`DELETE` sur `USER_RIGHT`. En revanche l'utilisateur doit
**se reconnecter**, les droits étant mis en cache côté client.

### Diagnostic complet du transfert « commande fournisseur »

Quand le transfert échoue pour un seul compte (`ID_COMMANDE_ELEMENT is not in
table /FACTURE_FOURNISSEUR_ELEMENT/`), le problème est rarement un droit :
c'est le **schéma** utilisé par la session, donc la société courante. Le
script ci-dessous enchaîne tous les tests et donne un verdict :

```sh
scripts/diagnostic-transfert-fournisseur.sh                  # rapport (erp vs abe)
scripts/diagnostic-transfert-fournisseur.sh -1 yves -2 gis   # par prénom
scripts/diagnostic-transfert-fournisseur.sh -f -n            # simulation des correctifs
scripts/diagnostic-transfert-fournisseur.sh -f                # application
```

Étapes enchaînées :

1. **configuration réellement utilisée par le client** (`main.properties`) —
   si le client pointe ailleurs que la base testée, un avertissement est
   affiché, car les résultats ne vaudraient rien ;
2. **structure du transfert, schéma par schéma** : présence de la table
   `FACTURE_FOURNISSEUR_ELEMENT` et de sa colonne `ID_COMMANDE_ELEMENT` dans
   *tous* les schémas de la base (c'est le contrôle clé) ;
3. **droits effectifs** des deux comptes et leur différentiel (délégué à
   `test-droits-utilisateur.sh`, qui doit être dans le même dossier) ;
4. **société mémorisée par le client** : `User.properties`, clé `LastSociete`
   — le client retient la dernière société utilisée et la propose par défaut
   à la connexion ; c'est elle qui détermine le schéma employé ;
5. **verdict global**, et avec `-f`, application des correctifs (structure
   puis droits).

> Le script est **strictement read-only par défaut**. `-f` est la seule option
> qui écrit, `-n` fait_simuler sans écrire.

Le script est validé de bout en bout contre un vrai PostgreSQL (pglite, sans
installation) avec des tables créées comme OpenConcerto les crée — noms de
tables et de colonnes en MAJUSCULES, entre guillemets :

```sh
npm install @electric-sql/pglite
bash tests/sql/e2e-droits.sh
```

## 6. Arrêt et suppression

```sh
docker compose stop      # réversible, données conservées
docker compose start
docker compose down      # supprime les conteneurs, conserve le volume pgdata
docker compose down -v   # supprime AUSSI les données
```

## 7. Déployer dans une VM Debian (sans interface graphique)

Quand la machine hôte n'a pas les droits pour faire tourner Podman
rootless (pas de plage d'UID secondaires), on peut faire tourner la stack
dans une VM Debian, où l'on est root : Docker n'y pose aucun problème.

- `scripts/create-debian-vm.sh` crée la VM (QEMU, netboot, preseed minimal :
  **aucun bureau**, locale `fr_FR.UTF-8`, compte `oc` avec `sudo` sans
  mot de passe, SSH sur le port 2222) ;
- `scripts/install-qemu-noroot.sh` installe QEMU sans droits administrateur,
  en résolvant les bibliothèques manquantes ;
- `scripts/deploy-oc176-in-vm.sh` installe Docker dans la VM et y déploie
  la stack PostgreSQL + Adminer (rien d'autre : ni bureau, ni LibreOffice).

```sh
bash deploy-oc176-in-vm.sh                       # Docker + PostgreSQL + Adminer
bash deploy-oc176-in-vm.sh --dump base.dumpsql   # et restauration du dump
bash deploy-oc176-in-vm.sh --purge-desktop       # nettoie un bureau installé par erreur
```

Depuis l'hôte, les services de la VM s'atteignent par tunnel SSH :

```sh
ssh -p 2222 -L 8082:127.0.0.1:8082 -L 5433:127.0.0.1:5433 oc@127.0.0.1
```

## Pièges connus

- **`docker compose exec` s'exécute en root** : `psql`/`pg_restore` lancés sans
  `-U` tentent alors une connexion avec le rôle `root`, qui n'existe pas
  (`FATAL: le rôle « root » n'existe pas`). Toujours passer `-U openconcerto`,
  ou `docker compose exec -u postgres`.
- **`PROVIDER` dans `CREATE DATABASE`** : refusé par PostgreSQL 17
  (`option « provider » non reconnue`). Une base ICU suppose un cluster
  initialisé avec `--locale-provider=icu` ; sur ce cluster libc, s'en tenir à
  la locale libc.
- **Sauvegardes cumulées** : chaque restauration écrit un dump complet de
  l'ancienne base dans `oc-restore-backup-<date>/`, et chaque copie ajoute un
  fichier dans `dumps/`. Penser à purger : `ls -lh oc-restore-backup-* dumps/`.
- **Version des outils** : un dump produit par `pg_dump` 17 ou 18 n'est pas
  lisible par un `pg_restore` plus ancien. Utiliser les outils du conteneur
  (`docker compose exec db pg_restore …`) plutôt que ceux de l'hôte s'ils
  diffèrent.
- **Port 5432** : publié ici sur 5433 pour ne pas entrer en conflit avec le
  cluster natif. Si le natif est arrêté, `PG_HOST_PORT=5432` dans `.env` suffit.
- **Persistance** : les données vivent dans le volume nommé `pgdata`, pas dans
  le système de fichiers du conteneur.
- Ce dossier ne contient pas de client OpenConcerto : l'archive officielle
  1.7.6 multiposte se récupère via `scripts/build-jar-with-curl.sh`
  (`SKIP_BUILD=1` pour seulement télécharger et extraire).
