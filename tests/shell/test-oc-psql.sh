#!/bin/sh
#
# Tests de scripts/oc-psql.sh, sans Docker : un faux `docker` est place en tete
# de PATH et journalise les appels.
#
# Couvre les cas reels :
#   1. detection du conteneur par le port publie 5433 ;
#   2. repli sur le premier conteneur PostgreSQL si le port n'est pas publie ;
#   3. aucun conteneur : message clair, code de sortie non nul ;
#   4. role lu dans l'environnement du conteneur (POSTGRES_USER) ;
#   5. base lue dans l'environnement (POSTGRES_DB) quand elle existe ;
#   6. base deduite quand POSTGRES_DB n'existe plus (base restauree) ;
#   7. plusieurs bases OpenConcerto : refus explicite, -d obligatoire ;
#   8. -d force la base ;
#   9. --no-password : ecrit l'empreinte de la chaine vide ;
#  10. --password : ecrit l'empreinte du mot de passe fourni ;
#  11. -l liste les bases ;
#  12. -n n'execute rien (dry-run) ;
#  13. -f passe le fichier sur stdin, sans TTY ;
#  14. aucune invocation de `docker compose` (le piege du .env manquant) ;
#  15. option inconnue : erreur explicite.
#
# Usage : sh tests/shell/test-oc-psql.sh
#
set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$ROOT/scripts/oc-psql.sh"
WORK=$(mktemp -d)
FAKEBIN="$WORK/bin"
mkdir -p "$FAKEBIN"
PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); printf 'OK     %s\n' "$*"; }
ko()   { FAIL=$((FAIL + 1)); printf 'ECHEC  %s\n' "$*"; }
check() { # check <libelle> <attendu> <obtenu>
    if [ "$2" = "$3" ]; then ok "$1"; else ko "$1 : attendu <$2>, obtenu <$3>"; fi
}
contains() { # contains <libelle> <motif> <texte>
    if printf '%s' "$3" | grep -qF -- "$2"; then ok "$1"; else ko "$1 : <$2> absent de <$3>"; fi
}

# ------------------------------------------------------------- faux docker
# Contenu pilote par les fichiers de $WORK :
#   containers   : lignes "nom<TAB>image" renvoyees par `docker ps --format`
#   env_<nom>    : lignes KEY=VALUE renvoyees par `docker inspect -f`
#   dbs_<nom>    : bases renvoyees par la requete de liste
#   envextra     : 1 si `docker inspect` doit echouer
cat > "$FAKEBIN/docker" <<'FAKE'
#!/bin/sh
W=$(dirname "$0")/..
LOG="$W/calls.log"
printf '%s\n' "docker $*" >> "$LOG"

case "$1" in
    ps)
        case "$*" in
            *publish=*)
                port=$(printf '%s' "$*" | sed -n 's/.*publish=\([0-9]*\).*/\1/p')
                [ -f "$W/port_$port" ] && cat "$W/port_$port"
                exit 0 ;;
        esac
        [ -f "$W/containers" ] && cat "$W/containers"
        exit 0 ;;
    inspect)
        name=$(printf '%s' "$*" | awk '{print $NF}')
        if [ -f "$W/inspect_fail" ]; then
            echo "Error: No such object: $name" >&2
            exit 1
        fi
        if printf '%s' "$*" | grep -q 'Config.Env'; then
            [ -f "$W/env_$name" ] && cat "$W/env_$name"
            exit 0
        fi
        echo "[]"
        exit 0 ;;
    exec)
        # docker exec [-i|-it] <conteneur> psql ...
        shift
        [ "${1:-}" = "-i" ] || [ "${1:-}" = "-it" ] && shift
        name="$1"; shift
        # requete de liste des bases ?
        if printf '%s' "$*" | grep -q 'pg_database'; then
            [ -f "$W/dbs_$name" ] && cat "$W/dbs_$name"
            exit 0
        fi
        # sinon : execution reelle demandee, on la journalise (sur UNE ligne :
        # le SQL peut contenir des retours a la ligne)
        flat=$(printf '%s' "$*" | tr '\n' ' ')
        printf '%s\n' "EXEC $name :: $flat" >> "$LOG"
        if [ -n "${FAKE_STDIN_LOG:-}" ] && [ ! -t 0 ]; then
            cat > "$FAKE_STDIN_LOG"
        fi
        [ -f "$W/exec_output" ] && cat "$W/exec_output"
        exit 0 ;;
esac
exit 0
FAKE
chmod +x "$FAKEBIN/docker"

reset_case() {
    rm -f "$WORK/calls.log" "$WORK/containers" "$WORK/port_5433" \
          "$WORK"/env_* "$WORK"/dbs_* "$WORK/inspect_fail" "$WORK/exec_output"
    : > "$WORK/calls.log"
}

run() { # run <args...> -> code de sortie dans $RC, sortie dans $OUT
    RC=0
    OUT=$(PATH="$FAKEBIN:$PATH" sh "$SCRIPT" "$@" 2>&1) || RC=$?
}

# ------------------------------------------------------------------ cas 1
reset_case
printf 'openconcerto176-db-1\tpostgres:17-bookworm\n' > "$WORK/containers"
printf 'openconcerto176-db-1\n' > "$WORK/port_5433"
printf 'POSTGRES_USER=openconcerto\nPOSTGRES_PASSWORD=x\nPOSTGRES_DB=OpenConcerto\n' > "$WORK/env_openconcerto176-db-1"
printf 'OpenConcerto\n' > "$WORK/dbs_openconcerto176-db-1"
run -n -c 'select 1'
check "cas 1 : code de sortie" "0" "$RC"
contains "cas 1 : conteneur detecte par le port 5433" "conteneur openconcerto176-db-1" "$OUT"
contains "cas 1 : role detecte" "role openconcerto" "$OUT"
contains "cas 1 : base detectee" "base OpenConcerto" "$OUT"
contains "cas 1 : commande docker exec" "docker exec -i openconcerto176-db-1 psql" "$OUT"

# ------------------------------------------------------------------ cas 2
reset_case
printf 'autre-db-1\tpostgres:16-alpine\n' > "$WORK/containers"
printf 'POSTGRES_USER=postgres\nPOSTGRES_DB=OpenConcerto\n' > "$WORK/env_autre-db-1"
printf 'OpenConcerto\n' > "$WORK/dbs_autre-db-1"
run -n
check "cas 2 : repli sur le conteneur PostgreSQL" "0" "$RC"
contains "cas 2 : conteneur trouve par l'image" "conteneur autre-db-1" "$OUT"

# ------------------------------------------------------------------ cas 3
reset_case
printf 'web-1\tnginx:alpine\n' > "$WORK/containers"
run -n
[ "$RC" -ne 0 ] && ok "cas 3 : aucun conteneur => code non nul" || ko "cas 3 : code de sortie $RC"
contains "cas 3 : message explicite" "Aucun conteneur PostgreSQL" "$OUT"
contains "cas 3 : conseil -C" "-C <conteneur>" "$OUT"

# ------------------------------------------------------------------ cas 4
reset_case
printf 'db-1\tpostgres:17\n' > "$WORK/containers"
printf 'POSTGRES_USER=abe\nPOSTGRES_DB=OpenConcerto\n' > "$WORK/env_db-1"
printf 'OpenConcerto\n' > "$WORK/dbs_db-1"
run -n
contains "cas 4 : role lu dans l'environnement" "role abe" "$OUT"

# ------------------------------------------------------------------ cas 5
reset_case
printf 'db-1\tpostgres:17\n' > "$WORK/containers"
printf 'POSTGRES_USER=openconcerto\nPOSTGRES_DB=OpenConcertoKineticTherm\n' > "$WORK/env_db-1"
printf 'OpenConcerto\nOpenConcertoKineticTherm\n' > "$WORK/dbs_db-1"
run -n
contains "cas 5 : POSTGRES_DB prioritaire" "base OpenConcertoKineticTherm" "$OUT"

# ------------------------------------------------------------------ cas 6
reset_case
printf 'db-1\tpostgres:17\n' > "$WORK/containers"
printf 'POSTGRES_USER=openconcerto\nPOSTGRES_DB=BaseDisparue\n' > "$WORK/env_db-1"
printf 'OpenConcertoKineticTherm\n' > "$WORK/dbs_db-1"
run -n
contains "cas 6 : base deduite quand POSTGRES_DB a disparu" "base OpenConcertoKineticTherm" "$OUT"

# ------------------------------------------------------------------ cas 7
reset_case
printf 'db-1\tpostgres:17\n' > "$WORK/containers"
printf 'POSTGRES_USER=openconcerto\n' > "$WORK/env_db-1"
printf 'OpenConcerto\nOpenConcerto42\n' > "$WORK/dbs_db-1"
run -n
[ "$RC" -ne 0 ] && ok "cas 7 : plusieurs bases => refus" || ko "cas 7 : devrait echouer"
contains "cas 7 : les deux bases listees" "OpenConcerto42" "$OUT"
contains "cas 7 : conseil -d" "choisissez la base avec -d" "$OUT"

# ------------------------------------------------------------------ cas 8
reset_case
printf 'db-1\tpostgres:17\n' > "$WORK/containers"
printf 'POSTGRES_USER=openconcerto\n' > "$WORK/env_db-1"
printf 'OpenConcerto\nOpenConcerto42\n' > "$WORK/dbs_db-1"
run -n -d OpenConcerto42
check "cas 8 : -d force la base" "0" "$RC"
contains "cas 8 : base choisie" "base OpenConcerto42" "$OUT"

# ------------------------------------------------------------------ cas 9
reset_case
printf 'db-1\tpostgres:17\n' > "$WORK/containers"
printf 'POSTGRES_USER=openconcerto\nPOSTGRES_DB=OpenConcerto\n' > "$WORK/env_db-1"
printf 'OpenConcerto\n' > "$WORK/dbs_db-1"
run --no-password abe
check "cas 9 : --no-password s'execute" "0" "$RC"
EXEC=$(grep '^EXEC' "$WORK/calls.log" || true)
contains "cas 9 : requete sur USER_COMMON" 'USER_COMMON' "$EXEC"
contains "cas 9 : empreinte de la chaine vide" "2jmj7l5rSw0yVb/vlWAYkK/YBwk=" "$EXEC"
contains "cas 9 : cible le login abe" "lower('abe')" "$EXEC"
contains "cas 9 : verification incluse" "sans_mot_de_passe" "$EXEC"

# ----------------------------------------------------------------- cas 10
reset_case
printf 'db-1\tpostgres:17\n' > "$WORK/containers"
printf 'POSTGRES_USER=openconcerto\nPOSTGRES_DB=OpenConcerto\n' > "$WORK/env_db-1"
printf 'OpenConcerto\n' > "$WORK/dbs_db-1"
run --password abe openconcerto
check "cas 10 : --password s'execute" "0" "$RC"
EXEC=$(grep '^EXEC' "$WORK/calls.log" || true)
EXPECTED=$(printf '%s' 'openconcerto' | openssl dgst -sha1 -binary | base64 | tr -d '\n')
contains "cas 10 : empreinte SHA1+Base64 du mot de passe" "$EXPECTED" "$EXEC"

# ----------------------------------------------------------------- cas 11
reset_case
printf 'db-1\tpostgres:17\n' > "$WORK/containers"
printf 'POSTGRES_USER=openconcerto\nPOSTGRES_DB=OpenConcerto\n' > "$WORK/env_db-1"
printf 'OpenConcerto\nOpenConcerto42\n' > "$WORK/dbs_db-1"
run -l
check "cas 11 : -l s'execute" "0" "$RC"
contains "cas 11 : bases listees" "OpenConcerto42" "$OUT"
if grep -q '^EXEC' "$WORK/calls.log"; then ko "cas 11 : -l ne doit rien executer"; else ok "cas 11 : -l ne modifie rien"; fi

# ----------------------------------------------------------------- cas 12
reset_case
printf 'db-1\tpostgres:17\n' > "$WORK/containers"
printf 'POSTGRES_USER=openconcerto\nPOSTGRES_DB=OpenConcerto\n' > "$WORK/env_db-1"
printf 'OpenConcerto\n' > "$WORK/dbs_db-1"
run -n --no-password abe
check "cas 12 : dry-run sort en 0" "0" "$RC"
if grep -q '^EXEC' "$WORK/calls.log"; then ko "cas 12 : dry-run a execute du SQL"; else ok "cas 12 : dry-run n'execute rien"; fi
contains "cas 12 : commande affichee" "docker exec" "$OUT"

# ----------------------------------------------------------------- cas 13
reset_case
printf 'db-1\tpostgres:17\n' > "$WORK/containers"
printf 'POSTGRES_USER=openconcerto\nPOSTGRES_DB=OpenConcerto\n' > "$WORK/env_db-1"
printf 'OpenConcerto\n' > "$WORK/dbs_db-1"
printf 'select 42;\n' > "$WORK/q.sql"
export FAKE_STDIN_LOG="$WORK/stdin.txt"
run -f "$WORK/q.sql"
unset FAKE_STDIN_LOG
check "cas 13 : -f s'execute" "0" "$RC"
STDIN_CONTENT=$(cat "$WORK/stdin.txt" 2>/dev/null || true)
check "cas 13 : le fichier passe sur stdin" "select 42;" "$STDIN_CONTENT"
if grep -q 'exec -it' "$WORK/calls.log"; then ko "cas 13 : -f ne doit pas demander de TTY"; else ok "cas 13 : pas de TTY avec -f"; fi

# ----------------------------------------------------------------- cas 14
if grep -q 'compose' "$WORK/calls.log" 2>/dev/null; then
    ko "cas 14 : le script appelle docker compose"
else
    ok "cas 14 : aucun appel a docker compose (pas de .env requis)"
fi
if grep -q 'compose' "$SCRIPT"; then
    contains "cas 14 : compose seulement mentionne en commentaire" '# Pourquoi ce script' "$(head -n 8 "$SCRIPT")"
else
    ok "cas 14 : docker compose absent du script"
fi

# ----------------------------------------------------------------- cas 15
reset_case
printf 'db-1\tpostgres:17\n' > "$WORK/containers"
run --option-qui-nexiste-pas
[ "$RC" -ne 0 ] && ok "cas 15 : option inconnue => erreur" || ko "cas 15 : devrait echouer"
contains "cas 15 : message clair" "option inconnue" "$OUT"

printf '\nControles : %s | echecs : %s\n' "$PASS" "$FAIL"
if [ "$FAIL" -eq 0 ]; then
    printf 'RESULTAT : OK\n'
    rm -rf "$WORK"
else
    printf 'RESULTAT : ECHEC (fichiers de travail conserves dans %s)\n' "$WORK"
    exit 1
fi
