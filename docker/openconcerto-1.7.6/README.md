# Stack Docker pour OpenConcerto 1.7.6

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

Le client lit sa configuration dans `~/.config/OpenConcerto/main.properties`
(chemin affiché au démarrage par `OpenConcerto.sh`). Deux options :

- lancer `/opt/openconcerto/OpenConcerto-Configuration.sh` et renseigner
  hôte `127.0.0.1`, port `5433`, base, utilisateur, mot de passe ;
- ou dupliquer le profil de configuration existant avant de le modifier, pour
  pouvoir revenir en arrière.

Vérifier ensuite dans le log de démarrage la ligne `Ip:127.0.0.1:5433` — c'est
elle qui dit à quelle base le client parle.

## 5. Arrêt et suppression

```sh
docker compose stop      # réversible, données conservées
docker compose start
docker compose down      # supprime les conteneurs, conserve le volume pgdata
docker compose down -v   # supprime AUSSI les données
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
