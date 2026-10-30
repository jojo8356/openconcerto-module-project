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
