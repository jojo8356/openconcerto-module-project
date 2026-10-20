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

## 2. Aligner la collation sur la base source

Un tri de texte diffère selon la collation. Sur la base d'origine :

```sh
sudo -u postgres psql -d OpenConcertoKineticTherm -Atc \
  "select datcollate, datctype, pg_encoding_to_char(encoding) from pg_database where datname='OpenConcertoKineticTherm'"
```

Si la réponse est autre chose que `C.UTF-8` (par exemple `fr_FR.UTF-8`), il faut
que cette locale existe dans le conteneur avant `initdb`. L'image Debian le
permet, l'image alpine/musl non :

```sh
docker compose exec db bash -c \
  'localedef -i fr_FR -c -f UTF-8 -A /usr/share/locale/locale.alias fr_FR.UTF-8 && locale -a | grep -i fr_FR'
```

Cette génération doit précéder la première initialisation du volume ; si le
volume existe déjà, `docker compose down -v` (perte des données du conteneur)
puis relancer.

## 3. Restaurer le dump 1.7.6

Avec le script du dépôt, en visant le port publié :

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
