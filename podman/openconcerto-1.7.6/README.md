# Stack Podman pour OpenConcerto 1.7.6

Équivalent de `docker/openconcerto-1.7.6/`, mais **sans Docker** : ni le
binaire `docker`, ni le plugin `docker compose` ne sont requis. Seul `podman`
(et `podman-compose`) est utilisé.

## 0. Prérequis

```zsh
podman --version
podman compose version
psql --version
```

- `podman` 4 ou plus (paquet `podman` sur Debian/Ubuntu, `podman` sur
  Fedora/RHEL) ;
- un fournisseur compose : `podman-compose` (paquet `podman-compose`) ou
  `podman compose`, qui le délègue ;
- le client PostgreSQL (`psql`, `pg_dump`, `pg_restore`) : paquet
  `postgresql-client` ;
- `sudo`, pour lire la base native (le rôle `postgres` n'a pas accès au
  dossier de l'utilisateur).

En rootless, le socket de l'API peut être activé pour que les outils
compose y accèdent :

```zsh
systemctl --user enable --now podman.socket
```

## 1. Installer la stack

```zsh
mkdir -p ~/oc-176-podman/dumps
cd ~/oc-176-podman
for f in compose.yaml compose.fr_FR.yaml Containerfile; do
  curl -fsSL -H "Accept: application/vnd.github.raw" \
    "https://api.github.com/repos/jojo8356/openconcerto-module-project/contents/podman/openconcerto-1.7.6/$f?ref=arena/61954a71-openconcerto-module-project" \
    -o "$f"
done
for f in podman-openconcerto.sh restore-openconcerto-dump.sh fix-facture-fournisseur-all-schemas.sh diagnostic-transfert-fournisseur.sh test-droits-utilisateur.sh switch-openconcerto-client-db.sh; do
  curl -fsSL -H "Accept: application/vnd.github.raw" \
    "https://api.github.com/repos/jojo8356/openconcerto-module-project/contents/scripts/$f?ref=arena/61954a71-openconcerto-module-project" \
    -o "$f"
done
chmod +x podman-openconcerto.sh restore-openconcerto-dump.sh fix-facture-fournisseur-all-schemas.sh diagnostic-transfert-fournisseur.sh test-droits-utilisateur.sh switch-openconcerto-client-db.sh
cp .env.example .env 2>/dev/null || true
```

Si `.env.example` n'est pas présent, crée le fichier à la main :

```zsh
cd ~/oc-176-podman
printf 'POSTGRES_USER=openconcerto\nPOSTGRES_PASSWORD=openconcerto\nPOSTGRES_DB=OpenConcerto\nPG_HOST_PORT=5433\nADMINER_PORT=8082\n' > .env
grep POSTGRES_PASSWORD .env
```

Le mot de passe du rôle SQL est celui utilisé par le client OpenConcerto
(`openconcerto` par défaut).

## 2. Démarrer

```zsh
bash ~/oc-176-podman/podman-openconcerto.sh up
bash ~/oc-176-podman/podman-openconcerto.sh status
```

PostgreSQL est publié sur `127.0.0.1:5433` (le cluster natif occupe déjà
5432), Adminer sur `http://127.0.0.1:8082`.

Si la stack **Docker** tourne déjà sur 5433, déplace la stack Podman :

```zsh
sed -i 's/^PG_HOST_PORT=.*/PG_HOST_PORT=5434/' ~/oc-176-podman/.env
```

Le port est relu automatiquement dans `.env` par le script (l'option
`--port` reste prioritaire), donc `up`, `copy`, `client` et `diagnose` restent
cohérents.

Si la base source est en `fr_FR.UTF-8`, il faut une image qui contient la
locale ; le volume doit alors être vierge :

```zsh
bash ~/oc-176-podman/podman-openconcerto.sh up --fr
```

## 3. Copier la base native dans le conteneur

```zsh
bash ~/oc-176-podman/podman-openconcerto.sh copy
```

La commande dump la base native (`OpenConcertoKineticTherm` par défaut),
la restaure dans le conteneur, applique le correctif
`FACTURE_FOURNISSEUR_ELEMENT.ID_COMMANDE_ELEMENT` sur **tous** les schémas,
puis contrôle le résultat. Le plan peut être affiché sans rien écrire :

```zsh
bash ~/oc-176-podman/podman-openconcerto.sh copy --dry-run
```

Un dump de la base du conteneur, et l'inverse :

```zsh
bash ~/oc-176-podman/podman-openconcerto.sh dump ~/oc-176-podman/dumps/backup-OpenConcerto.dumpsql
bash ~/oc-176-podman/podman-openconcerto.sh restore ~/oc-176-podman/dumps/backup-OpenConcerto.dumpsql
```

## 4. Brancher le client 1.7.6

```zsh
bash ~/oc-176-podman/podman-openconcerto.sh client container
cd /opt/openconcerto && sh OpenConcerto.sh
```

Le journal du client doit indiquer `Ip:127.0.0.1:5433` et la base
`OpenConcerto`. Retour à la base native :

```zsh
bash ~/oc-176-podman/podman-openconcerto.sh client native
```

## 5. Contrôler le transfert « commande fournisseur »

```zsh
bash ~/oc-176-podman/podman-openconcerto.sh diagnose
```

La batterie complète (configuration du client, structure du transfert schéma
par schéma, droits effectifs de `erp` et `abe`, société mémorisée par le
client, verdict) est en lecture seule. `-f` applique les correctifs, `-n`
simule.

## Différences avec la version Docker

| Point | Docker | Podman |
|---|---|---|
| Commande | `docker compose` | `podman compose` (ou `podman-compose`) |
| Nom du projet | clé `name:` du fichier | option `-p openconcerto176` |
| Nom du conteneur | imposé par `container_name` | laissé à Podman, retrouvé par `ps -q db` |
| Montage de `./dumps` | `:ro` | `:ro,z` (relabelisation SELinux) |
| Images | `postgres:17-bookworm` | `docker.io/library/postgres:17-bookworm` (registre explicite) |
| Image locale | `Dockerfile` | `Containerfile` |
| Exécution dans le conteneur | `docker compose exec -T db` | `podman exec -i <id>` (identifiant obtenu par `ps -q db`) |

Le fichier `compose.yaml` est volontairement compatible avec les deux
outils : il ne contient ni `name:`, ni `container_name`, ni `version:`.

## Mode « sans root » (ni sudo, ni plage d'UID/GID secondaires)

Quand l'utilisateur n'a **ni** les droits administrateur **ni** de plage
d'UID/GID secondaires (`/etc/subuid`), deux verrous se lèvent sans root :

```zsh
bash ~/oc-176-podman/podman-openconcerto.sh up --no-root
```

Ce mode :

1. active `ignore_chown_errors = "true"` dans
   `~/.config/containers/storage.conf` (pour ton seul utilisateur) : les
   fichiers `root:shadow` des images ne sont plus un obstacle à
   l'extraction ;
2. démarre PostgreSQL **sans compose**, en `podman run` direct, avec
   `--userns=keep-id` : le processus PostgreSQL s'exécute avec l'UID de
   l'utilisateur — le seul identifiant mappable en l'absence de plage
   secondaire — et le répertoire de données est le dossier `./pgdata` de
   l'hôte, déjà possédé par l'utilisateur.

Conséquences à connaître :

- le conteneur s'appelle `openconcerto176-db` (pas de projet compose) ;
- **Adminer n'est pas démarré** dans ce mode (le port 8082 reste libre) ;
- la socket Unix de PostgreSQL est dans `/tmp` à l'intérieur du conteneur
  (`-c unix_socket_directories=/tmp`) : sans effet pour le client, qui passe
  par TCP ;
- les données vivent dans `~/oc-176-podman/pgdata` (dossier de l'hôte) ;
- `copy`, `client`, `diagnose`, `sql` et `dump` fonctionnent comme d'habitude :
  ils retrouvent le conteneur par son nom.

Le mode normal (`up`, sans `--no-root`) reste préférable : il donne un
conteneneur `postgres` classique, avec Adminer et une gestion standard des
permissions.

## Dépannage : « potentially insufficient UIDs or GIDs available in user namespace »

Symptôme (Podman **rootless**) :

```
Error: copying system image from manifest list: writing blob: adding layer
with blob "sha256:…"/""/"sha256:…": unpacking failed (error: exit status 1;
output: potentially insufficient UIDs or GIDs available in user namespace
(requested 0:42 for /etc/gshadow): Check /etc/subuid and /etc/subgid if
configured locally and run "podman system migrate")
```

Cause : en rootless, chaque fichier de l'image est rattaché à un UID/GID
« secondaire » de l'utilisateur. Les images Debian contiennent des fichiers
`root:shadow` (GID 42) : il faut une plage d'UID/GID secondaires assez large
dans `/etc/subuid` et `/etc/subgid`, sinon l'extraction échoue. L'erreur
suivante (`no container with name or ID "openconcerto176_db_1" found`) n'est
qu'une conséquence : le conteneur n'a jamais été créé.

Vérification :

```zsh
grep "^$(id -un):" /etc/subuid /etc/subgid
```

Si rien ne s'affiche, il faut créer la plage (une fois, avec `sudo`) :

```zsh
sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$(id -un)"
```

Si `usermod` ne connaît pas `--add-subuids` (paquet `shadow` trop ancien) :

```zsh
sudo tee -a /etc/subuid >/dev/null <<EOF
$(id -un):100000:65536
EOF
sudo tee -a /etc/subgid >/dev/null <<EOF
$(id -un):100000:65536
EOF
```

Puis, dans tous les cas, appliquer la nouvelle plage au stockage existant et
relancer :

```zsh
podman system migrate
podman pull docker.io/library/postgres:17-bookworm
bash ~/oc-176-podman/podman-openconcerto.sh up
```

`podman system migrate` déplace le stockage : c'est long, mais sans
risque pour les données.

**Contournement sans droits administrateur** : ignorer les erreurs de
propriété lors de l'extraction, pour ce seul utilisateur :

```zsh
python3 - <<'PYCODE'
import pathlib
p = pathlib.Path.home() / ".config/containers/storage.conf"
p.parent.mkdir(parents=True, exist_ok=True)
t = p.read_text() if p.exists() else ""
if "ignore_chown_errors" in t:
    print("déjà présent :", p)
else:
    if "[storage.options]" in t:
        t = t.replace("[storage.options]", '[storage.options]\nignore_chown_errors = "true"', 1)
    else:
        t = t.rstrip() + '\n\n[storage.options]\nignore_chown_errors = "true"\n'
    p.write_text(t)
    print("ajouté dans", p)
PYCODE
```

Le script `podman-openconcerto.sh up` contrôle la présence de la plage
**avant** de tirer les images, et affiche cette procédure si elle manque.

## Notes

- **Ports** : en rootless, un port < 1024 demanderait `podman unshare` ou
  `systemd.socket` ; la stack utilise 5433 et 8082, donc aucun privilège
  particulier n'est requis.
- **SELinux** : l'option `z` du montage est ignorée sur les systèmes sans
  SELinux, et indispensable sur Fedora/RHEL.
- **Rôle SQL** : `podman-openconcerto.sh client container` aligne le mot de
  passe du rôle du conteneur sur celui du client (`ALTER ROLE`). `--no-role`
  permet de ne pas le faire.
- **Aucune commande Docker** n'est appelée par ce script ni par la stack.
