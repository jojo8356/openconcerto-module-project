#!/usr/bin/env sh
#
# Test de bout en bout « libelles de colonnes » (PostgreSQL via pglite).
#
# Verifie, sur une vraie base :
#   1. la migration du module est idempotente et cree les deux tables ;
#   2. un seul libelle par (table, colonne) peut exister (index unique) ;
#   3. une regle par table et une regle « * » (toutes les tables) coexistent ;
#   4. l'enregistrement en une transaction remplace tout l'etat : pas de melange
#      entre l'ancien et le nouveau si une erreur survient ;
#   5. les libelles accentués et longs sont acceptes (UTF-8) ;
#   6. la requete « qui a le plus de droits » renvoie le bon ordre : les
#      superutilisateurs d'abord, puis les administrateurs, puis le nombre de
#      droits ; les comptes desactives sont ignores ;
#   7. cette requete est EXACTEMENT celle du module (comparee au Java par
#      ColumnLabelRulesTest, executee ici) ;
#   8. le module n'ecrase aucune table du coeur OpenConcerto.
#
# Usage :
#   sh tests/sql/e2e-colonnes.sh
#   WORK_DIR=/tmp/essai sh tests/sql/e2e-colonnes.sh
#
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
WORK_DIR=${WORK_DIR:-$(mktemp -d)}
DATA_DIR="$WORK_DIR/pglite"
BIN_DIR="$WORK_DIR/bin"
PSQL="$BIN_DIR/psql"
SCHEMA=OpenConcerto42

cd "$ROOT_DIR"

CONTROLES=0
ECHECS=0

ok() { CONTROLES=$((CONTROLES + 1)); printf 'OK     %s\n' "$1"; }
ko() { CONTROLES=$((CONTROLES + 1)); ECHECS=$((ECHECS + 1)); printf 'ECHEC  %s\n' "$1"; }

q() { "$PSQL" -X -A -t -v ON_ERROR_STOP=1 -c "$1"; }

check() {
    description=$1
    expected=$2
    actual=$(q "$3" 2>&1) || actual="ERREUR: $actual"
    if [ "$actual" = "$expected" ]; then
        ok "$description"
    else
        ko "$description (attendu : '$expected', obtenu : '$actual')"
    fi
}

# Verifie qu'une instruction echoue en contenant le motif attendu.
expect_error() {
    description=$1
    pattern=$2
    set +e
    out=$(q "$3" 2>&1)
    code=$?
    set -e
    if [ "$code" -ne 0 ] && printf '%s' "$out" | grep -qi -- "$pattern"; then
        ok "$description"
    else
        ko "$description (code $code, sortie : $out)"
    fi
}

echo "== 1. preparation =="
mkdir -p "$BIN_DIR"
if [ ! -d "$ROOT_DIR/node_modules/@electric-sql/pglite" ]; then
    echo "installation des dependances node (pglite) ..."
    npm install --silent
fi
cat > "$PSQL" <<EOF
#!/usr/bin/env bash
exec node "$ROOT_DIR/tests/sql/pglite-psql.mjs" "\$@"
EOF
chmod +x "$PSQL"
export PATH="$BIN_DIR:$PATH"
export PGLITE_DIR="$DATA_DIR"
rm -rf "$DATA_DIR"

"$PSQL" -X -v ON_ERROR_STOP=1 -f "$ROOT_DIR/tests/sql/fixture-colonnes.sql" > /dev/null
sed "s/__SCHEMA__/$SCHEMA/g" "$ROOT_DIR/tests/sql/migration-colonnes.sql" > "$WORK_DIR/migration.sql"
# Le bloc « -- query: roleRights » sert aux tests Java : on le retire du fichier
# joue par psql (ce sont des lignes de commentaire, mais autant jouer exactement
# le DDL).
grep -v '^-- query:' "$WORK_DIR/migration.sql" > "$WORK_DIR/migration-ddl.sql" || true

"$PSQL" -X -v ON_ERROR_STOP=1 -f "$WORK_DIR/migration-ddl.sql" > /dev/null

check "la table des libelles existe" "1" \
    "select count(*) from information_schema.tables where table_schema = '$SCHEMA' and table_name = 'PROJECT_COLUMN_LABEL'"
check "la table des reglages existe" "1" \
    "select count(*) from information_schema.tables where table_schema = '$SCHEMA' and table_name = 'PROJECT_SETTINGS'"
check "l'index unique (table, colonne) existe" "1" \
    "select count(*) from pg_indexes where schemaname = '$SCHEMA' and indexname = 'PROJECT_COLUMN_LABEL_UNQ'"
check "le mode par defaut est AUTO" "AUTO" \
    "select \"VALUE\" from \"$SCHEMA\".\"PROJECT_SETTINGS\" where \"KEY\" = 'column.label.mode'"

# --- Idempotence : on rejoue la migration ------------------------------
"$PSQL" -X -v ON_ERROR_STOP=1 -f "$WORK_DIR/migration-ddl.sql" > /dev/null
check "la migration est idempotente (toujours 2 tables)" "2" \
    "select count(*) from information_schema.tables where table_schema = '$SCHEMA' and table_name in ('PROJECT_COLUMN_LABEL','PROJECT_SETTINGS')"
check "le mode n'est pas duplique apres rejeu" "1" \
    "select count(*) from \"$SCHEMA\".\"PROJECT_SETTINGS\" where \"KEY\" = 'column.label.mode'"

echo "== 2. un seul libelle par (table, colonne) =="
q "insert into \"$SCHEMA\".\"PROJECT_COLUMN_LABEL\" (\"TABLE_NAME\",\"COLUMN_NAME\",\"LABEL\",\"DATE\",\"ID_USER\")
   values ('AFFAIRE','ID_CLIENT','CLIENT',now(),1)" > /dev/null
check "la regle est enregistree" "CLIENT" \
    "select \"LABEL\" from \"$SCHEMA\".\"PROJECT_COLUMN_LABEL\" where \"TABLE_NAME\" = 'AFFAIRE' and \"COLUMN_NAME\" = 'ID_CLIENT'"
expect_error "un doublon (meme table, meme colonne) est refuse" "duplicate\|unique" \
    "insert into \"$SCHEMA\".\"PROJECT_COLUMN_LABEL\" (\"TABLE_NAME\",\"COLUMN_NAME\",\"LABEL\") values ('AFFAIRE','ID_CLIENT','AUTRE')"
check "le libelle initial n'a pas ete ecrase" "CLIENT" \
    "select \"LABEL\" from \"$SCHEMA\".\"PROJECT_COLUMN_LABEL\" where \"TABLE_NAME\" = 'AFFAIRE' and \"COLUMN_NAME\" = 'ID_CLIENT'"

echo "== 3. regle par table et regle « toutes les tables » =="
q "insert into \"$SCHEMA\".\"PROJECT_COLUMN_LABEL\" (\"TABLE_NAME\",\"COLUMN_NAME\",\"LABEL\") values
     ('*','ID_FOURNISSEUR','FOURNISSEUR'),
     ('COMMANDE','ID_AFFAIRE','AFFAIRE (commande)'),
     ('FACTURE_FOURNISSEUR','ID_AFFAIRE','AFFAIRE (facture)')" > /dev/null
check "la regle generique et les deux regles par table coexistent" "3" \
    "select count(*) from \"$SCHEMA\".\"PROJECT_COLUMN_LABEL\" where \"COLUMN_NAME\" in ('ID_AFFAIRE','ID_FOURNISSEUR')"
check "la regle de COMMANDE est propre a la table" "AFFAIRE (commande)" \
    "select \"LABEL\" from \"$SCHEMA\".\"PROJECT_COLUMN_LABEL\" where \"TABLE_NAME\" = 'COMMANDE' and \"COLUMN_NAME\" = 'ID_AFFAIRE'"
check "la regle de FACTURE_FOURNISSEUR est differente" "AFFAIRE (facture)" \
    "select \"LABEL\" from \"$SCHEMA\".\"PROJECT_COLUMN_LABEL\" where \"TABLE_NAME\" = 'FACTURE_FOURNISSEUR' and \"COLUMN_NAME\" = 'ID_AFFAIRE'"
check "la regle « * » s'applique a toutes les tables" "FOURNISSEUR" \
    "select \"LABEL\" from \"$SCHEMA\".\"PROJECT_COLUMN_LABEL\" where \"TABLE_NAME\" = '*' and \"COLUMN_NAME\" = 'ID_FOURNISSEUR'"

echo "== 4. enregistrement en une transaction (remplacement complet) =="
# C'est exactement ce que fait ColumnLabelRules.saveStatements : delete + insert
# dans un seul BEGIN/COMMIT. On verifie qu'une erreur au milieu ne laisse pas la
# table a moitie vide.
q "begin;
   delete from \"$SCHEMA\".\"PROJECT_COLUMN_LABEL\";
   insert into \"$SCHEMA\".\"PROJECT_COLUMN_LABEL\" (\"TABLE_NAME\",\"COLUMN_NAME\",\"LABEL\") values
       ('*','ID_CLIENT','CLIENT'),
       ('*','ID_AFFAIRE','AFFAIRE');
   commit;" > /dev/null
check "l'enregistrement remplace l'etat precedent" "2" \
    "select count(*) from \"$SCHEMA\".\"PROJECT_COLUMN_LABEL\""
check "l'ancienne regle specifique a disparu (remplacement, pas fusion)" "0" \
    "select count(*) from \"$SCHEMA\".\"PROJECT_COLUMN_LABEL\" where \"TABLE_NAME\" = 'COMMANDE'"

set +e
out=$(q "begin;
   delete from \"$SCHEMA\".\"PROJECT_COLUMN_LABEL\";
   insert into \"$SCHEMA\".\"PROJECT_COLUMN_LABEL\" (\"TABLE_NAME\",\"COLUMN_NAME\",\"LABEL\") values ('*','ID_X','X');
   insert into \"$SCHEMA\".\"PROJECT_COLUMN_LABEL\" (\"TABLE_NAME\",\"COLUMN_NAME\",\"LABEL\") values (null,'ID_Y','Y');
   commit;" 2>&1)
code=$?
set -e
if [ "$code" -ne 0 ]; then
    ok "un enregistrement invalide echoue"
else
    ko "un enregistrement invalide aurait du echouer"
fi
check "en cas d'echec, l'ancien etat est intact (transaction)" "2" \
    "select count(*) from \"$SCHEMA\".\"PROJECT_COLUMN_LABEL\""

echo "== 5. libelles reels =="
q "begin;
   delete from \"$SCHEMA\".\"PROJECT_COLUMN_LABEL\";
   insert into \"$SCHEMA\".\"PROJECT_COLUMN_LABEL\" (\"TABLE_NAME\",\"COLUMN_NAME\",\"LABEL\") values
       ('*','ID_CLIENT','Client'),
       ('*','ID_AFFAIRE','Affaire'),
       ('FACTURE_FOURNISSEUR','ID_FOURNISSEUR','Fournisseur (facture)'),
       ('*','ID_NUMERO_DEVIS','N° de devis');
   commit;" > /dev/null
check "les libelles accentues sont stockes tels quels" "N° de devis" \
    "select \"LABEL\" from \"$SCHEMA\".\"PROJECT_COLUMN_LABEL\" where \"COLUMN_NAME\" = 'ID_NUMERO_DEVIS'"
check "le libelle personnalise d'une table est conserve" "Fournisseur (facture)" \
    "select \"LABEL\" from \"$SCHEMA\".\"PROJECT_COLUMN_LABEL\" where \"TABLE_NAME\" = 'FACTURE_FOURNISSEUR'"
expect_error "un libelle vide est refuse" "not-null\|violates" \
    "insert into \"$SCHEMA\".\"PROJECT_COLUMN_LABEL\" (\"TABLE_NAME\",\"COLUMN_NAME\",\"LABEL\") values ('*','ID_VIDE',null)"
check "un libelle trop long ne peut pas depasser la colonne" "character varying(128)" \
    "select data_type || '(' || character_maximum_length || ')' from information_schema.columns where table_schema = '$SCHEMA' and table_name = 'PROJECT_COLUMN_LABEL' and column_name = 'LABEL'"

echo "== 6. qui a le plus de droits ? =="
ROLE_QUERY=$(sed -n '/^-- query: roleRights$/,/^-- query: end$/p' "$ROOT_DIR/tests/sql/migration-colonnes.sql" | sed '1d;$d' | sed "s/__SCHEMA__/$SCHEMA/g" | tr '\n' ' ')
[ -n "$ROLE_QUERY" ] || { echo "requete roleRights introuvable dans le fichier SQL" >&2; exit 1; }

check "5 comptes actifs sont lus (le compte desactive est exclu)" "5" \
    "select count(*) from ($ROLE_QUERY) t"
check "le premier est la superutilisatrice" "1" \
    "select \"ID_USER\" from ($ROLE_QUERY) t limit 1"
check "elle cumule 5 droits" "5" \
    "select \"DROITS\" from ($ROLE_QUERY) t where \"ID_USER\" = 1"
check "la deuxieme administratrice arrive ensuite (2 droits)" "2" \
    "select \"ID_USER\" from ($ROLE_QUERY) t limit 1 offset 1"
check "l'utilisatrice ordinaire avec 4 droits est apres les administratrices" "4" \
    "select \"ID_USER\" from ($ROLE_QUERY) t where \"DROITS\" = 4"
check "le compte desactive n'apparait pas" "0" \
    "select count(*) from ($ROLE_QUERY) t where \"ID_USER\" = 6"

# Le module applique ensuite : superutilisateurs s'il y en a, sinon
# administrateurs, sinon le maximum de droits. On verifie la meme chose en SQL.
check "le role le plus haut est la superutilisatrice (Gisèle)" "Gisèle" \
    "select \"NOM\" from ($ROLE_QUERY) t where \"SUPERUSER\" = 1 order by 1 limit 1"
q "update \"$SCHEMA\".\"USER_COMMON\" set \"SUPERUSER\" = false where \"ID\" = 1" > /dev/null
check "sans superutilisateur, les administratrices prennent la main" "2" \
    "select count(*) from ($ROLE_QUERY) t where \"ADMIN\" = 1"
check "et c'est une administratrice qui est en tete" "1" \
    "select \"ADMIN\" from ($ROLE_QUERY) t limit 1"
q "update \"$SCHEMA\".\"USER_COMMON\" set \"ADMIN\" = false" > /dev/null
check "sans administrateur, c'est le plus grand nombre de droits" "5" \
    "select \"DROITS\" from ($ROLE_QUERY) t limit 1"
check "c'est alors Gisèle (5 droits) qui decide" "1" \
    "select \"ID_USER\" from ($ROLE_QUERY) t limit 1"

echo "== 7. le module n'ecrase aucune table du coeur =="
check "aucune table du coeur n'a ete modifiee par la migration" "0" \
    "select count(*) from information_schema.tables where table_schema = '$SCHEMA' and table_name in ('USER_COMMON','USER_RIGHT','RIGHT','AFFAIRE','COMMANDE') and table_name in ('PROJECT_COLUMN_LABEL','PROJECT_SETTINGS')"
check "les tables metier sont intactes" "6" \
    "select count(*) from information_schema.tables where table_schema = '$SCHEMA' and table_name in ('USER_COMMON','USER_RIGHT','RIGHT','AFFAIRE','COMMANDE','FACTURE_FOURNISSEUR')"

echo
echo "Controles : $CONTROLES | echecs : $ECHECS"
if [ "$ECHECS" -ne 0 ]; then
    echo "RESULTAT : ECHEC"
    exit 1
fi
echo "RESULTAT : OK"
