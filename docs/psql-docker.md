# Passer du SQL à OpenConcerto quand il tourne sous Docker

Deux erreurs reviennent tout le temps :

```
no configuration file provided: not found
error while interpolating services.db.environment.POSTGRES_PASSWORD:
  required variable POSTGRES_PASSWORD is missing a value
```

Aucune des deux ne vient de PostgreSQL ni d'OpenConcerto :

| Message | Cause | Ce qu'il faut faire |
|---|---|---|
| `no configuration file provided` | `docker compose` cherche `docker-compose.yml` dans le dossier **courant** ; celui du dépôt est dans `docker/openconcerto-1.7.6/` | `cd docker/openconcerto-1.7.6`, ou `docker compose -f docker/openconcerto-1.7.6/docker-compose.yml …` |
| `required variable POSTGRES_PASSWORD is missing` | il n'y a pas de fichier `.env` à côté du `docker-compose.yml` (il est volontairement non versionné) | `cp .env.example .env` puis renseigner `POSTGRES_PASSWORD` — **ou** ne pas passer par compose du tout (voir ci-dessous) |

## La méthode qui marche toujours : `scripts/oc-psql.sh`

Le script parle **directement au conteneur déjà démarré**. Il ne lit pas
`docker-compose.yml`, donc il ne réclame **ni `.env`, ni mot de passe, ni
dossier courant**. Il détecte le conteneur, le rôle et la base.

```sh
sh scripts/oc-psql.sh                          # invite psql interactive
sh scripts/oc-psql.sh -c 'select now()'        # une requête
sh scripts/oc-psql.sh -f requete.sql           # un fichier
sh scripts/oc-psql.sh -l                       # lister les bases
sh scripts/oc-psql.sh -n -c 'select 1'         # dry-run : affiche la commande
```

Détection, dans cet ordre :

1. **conteneur** : celui qui publie le port **5433** (le port de la stack),
   sinon le premier conteneur `postgres`/`postgis` en cours ; forçable avec
   `-C <conteneur>` ou `OC_CONTAINER` ;
2. **rôle** : `POSTGRES_USER` de l'environnement du conteneur, sinon le premier
   superutilisateur ; forçable avec `-U` ;
3. **base** : `POSTGRES_DB` s'il existe encore, sinon l'unique base
   `OpenConcerto*`, sinon la seule base non système ; forçable avec `-d`.

En cas d'ambiguïté il **s'arrête** en listant les bases au lieu de deviner.

## Gisèle (`abe`) sans mot de passe

OpenConcerto stocke `Base64(SHA1(mot de passe))` dans
`"Common"."USER_COMMON"."PASSWORD"`. « Pas de mot de passe » = l'empreinte de la
**chaîne vide** ; le cœur reconnaît alors n'importe quelle saisie, y compris un
champ vide (`Login.connect`).

```sh
sh scripts/oc-psql.sh --no-password abe     # retire le mot de passe + vérifie
sh scripts/oc-psql.sh --password abe MDP    # (re)met un mot de passe
```

Le script affiche la ligne modifiée avec la colonne `sans_mot_de_passe`.

À la main, l'équivalent est :

```sql
update "Common"."USER_COMMON"
   set "PASSWORD" = '2jmj7l5rSw0yVb/vlWAYkK/YBwk='   -- Base64(SHA1(""))
 where lower("LOGIN") = 'abe';
select "LOGIN", "PASSWORD",
       ("PASSWORD" = '2jmj7l5rSw0yVb/vlWAYkK/YBwk=') as sans_mot_de_passe
  from "Common"."USER_COMMON" where lower("LOGIN") = 'abe';
```

> `set "PASSWORD" = null` fonctionne aussi : le cœur accepte `dbPass == null`.

### Précautions

1. **Un seul utilisateur doit porter ce login** : `Login.findUser` renvoie
   `MORE_THAN_ONE_USER` si plusieurs lignes correspondent.
2. **N'importe qui connaissant le login entre sous cette identité**, avec ses
   droits — y compris, pour Gisèle, ceux qui ouvrent le menu des libellés. À
   réserver à une session de test.
3. **Retour arrière** : `sh scripts/oc-psql.sh --password abe <ancien mot de passe>`
   (ou réinjecter l'empreinte notée avant la modification).

## Restaurer un dump dans le conteneur (`.dumpsql`, `.dumpsql.gz`)

Un dump OpenConcerto s'appelle `OC-v1.7.6-….dumpsql` ; il peut être **gzippé**
(`….dumpsql.gz`). Ce n'est pas parce que l'extension est `.dumpsql` que le
contenu est du SQL texte : c'est le plus souvent du `pg_dump -Fc`, qui commence
par les cinq octets `PGDMP`. On vérifie avant de restaurer :

```sh
file OC-v1.7.6-Noon_Dump_2026-10-09.dumpsql.gz
gunzip -c OC-v1.7.6-Noon_Dump_2026-10-09.dumpsql.gz | head -c 5; echo
# PGDMP  -> format -Fc    (pg_restore)
# --…    -> SQL texte     (psql)
```

Le script fait tout (détection du format, sauvegarde, restauration, contrôle) :

```sh
scripts/push-dump-to-docker.sh -f OC-v1.7.6-Noon_Dump_2026-10-09.dumpsql.gz -n   # plan
scripts/push-dump-to-docker.sh -f OC-v1.7.6-Noon_Dump_2026-10-09.dumpsql.gz      # exécute
```

Il détecte le conteneur qui publie le `5433`, lit `POSTGRES_USER` / `POSTGRES_DB`
dans le conteneur, **sauvegarde la base cible avant de la toucher**
(`backup-<base>-<date>.dump` à côté du dump) et refuse de continuer si la
sauvegarde est vide.

À la main, pour un dump `-Fc` gzippé :

```sh
gunzip -c OC-v1.7.6-Noon_Dump_2026-10-09.dumpsql.gz > /tmp/dump.dumpsql
docker cp /tmp/dump.dumpsql openconcerto176-db-1:/tmp/dump.dumpsql

# 1. sauvegarde de ce qu'il y a déjà
docker exec -i openconcerto176-db-1 sh -c 'pg_dump -U "$POSTGRES_USER" -Fc -d "$POSTGRES_DB"' > backup-$(date +%F).dump

# 2. base neuve (les données actuelles sont remplacées)
docker exec -i openconcerto176-db-1 sh -c 'dropdb -U "$POSTGRES_USER" "$POSTGRES_DB" && createdb -U "$POSTGRES_USER" -O "$POSTGRES_USER" "$POSTGRES_DB"'

# 3. restauration
docker exec -i openconcerto176-db-1 sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --no-privileges /tmp/dump.dumpsql'
```

### Le piège « existe déjà » (5 700 erreurs ignorées)

```
ERREUR: la contrainte « TR_COMMANDE_ID_COMMANDE_fkey » ... existe déjà
pg_restore: attention : erreurs ignorées lors de la restauration : 5700
```

Message à retenir : **existe déjà**. Sur une base vide c'est impossible. Donc
`pg_restore` a écrit dans une base qui contenait déjà le schéma `OpenConcerto42`
— soit le dump a été restauré deux fois, soit la cible n'était pas la base neuve
attendue.

C'est plus grave qu'une erreur bruyante : les `CREATE TABLE`, `ADD CONSTRAINT` et
`CREATE INDEX` échouent tous, mais les `COPY` peuvent **dupliquer** les données.
Vérifiez la base visée avant tout :

```sh
docker exec -i openconcerto176-db-1 sh -c 'psql -U "$POSTGRES_USER" -d LA_BASE -tAc "select count(*) from information_schema.tables where table_type = '"'"'BASE TABLE'"'"' and table_schema not in ('"'"'pg_catalog'"'"','"'"'information_schema'"'"')"'
```

`0` attendu avant de restaurer. Sinon :

```sh
docker exec -i openconcerto176-db-1 sh -c 'dropdb -U "$POSTGRES_USER" --if-exists LA_BASE && createdb -U "$POSTGRES_USER" -O "$POSTGRES_USER" LA_BASE'
docker exec -i openconcerto176-db-1 sh -c 'pg_restore -U "$POSTGRES_USER" -d LA_BASE --no-owner --no-privileges --exit-on-error /tmp/dump.dumpsql'
echo "code : $?"
```

`--exit-on-error` change tout : sur une base vide, la **première** erreur arrête
la restauration et s'affiche seule. Code `0` = restauration complète, sans avoir
à trier des milliers de lignes.

Deux points qui font échouer une restauration dans 90 % des cas :

- **`pg_restore` sort en 1 sans que les données soient en cause** : ce sont les
  propriétaires, extensions ou `COMMENT` de l'installation d'origine. Le code 2
  et plus est un vrai échec ; le code 1 se lit dans la sortie.
- **la collation** : un dump `fr_FR.UTF-8` restauré dans un cluster `C.UTF-8`
  échoue sur `CREATE DATABASE`. Voir la section locale de
  `docker/openconcerto-1.7.6/README.md` (override `docker-compose.fr_FR.yml`,
  qui exige un volume vierge).

Pour un dump **SQL texte** :

```sh
gunzip -c dump.sql.gz | docker exec -i openconcerto176-db-1 sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=0'
```

Si le fichier contient un `CREATE DATABASE`, il faut le jouer sur `postgres` et
non sur la base cible.

**Attention aux données reprises.** Un dump antérieur à une reprise des affaires
la remet à zéro : le compteur de `sql/attendu-reprise.sql` repassera au-dessus de
0 et `Aide > Reprendre les affaires des documents` aura de nouveau du travail.

## Sans le script : les commandes Docker utiles

```sh
# depuis le dossier de la stack (celui du docker-compose.yml)
cd docker/openconcerto-1.7.6
docker compose ps
docker compose exec db psql -U openconcerto -d OpenConcerto

# depuis n'importe où, sans compose ni .env
docker ps --filter publish=5433 --format '{{.Names}}'
docker exec -it openconcerto176-db-1 psql -U openconcerto -d OpenConcerto

# un fichier SQL sur stdin (le -T est indispensable, sinon le TTY avale le flux)
docker exec -T openconcerto176-db-1 psql -U openconcerto -d OpenConcerto < requete.sql
```

Piège documenté dans `docker/openconcerto-1.7.6/README.md` : `docker compose exec`
s'exécute en **root**. Sans `-U`, `psql` cherche le rôle `root` et échoue avec
`FATAL: le rôle « root » n'existe pas`.

## Vérifications

```sh
sh tests/shell/test-oc-psql.sh
```

38 contrôles, sans Docker : un faux `docker` est placé en tête de `PATH` et
journalise les appels. Les cas couverts incluent la détection par port puis par
image, l'absence de conteneur, `POSTGRES_DB` disparu après restauration,
plusieurs bases (refus), `-d` forcé, `--no-password` (empreinte exacte de la
chaîne vide), `--password`, `-l`, `-n` (aucune exécution), `-f` (stdin sans TTY)
et l'**absence totale d'appel à `docker compose`**.
