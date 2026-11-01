#!/usr/bin/env sh
#
# Diagnostic « affaire » des documents fournisseurs — LECTURE SEULE.
#
# Repond a la question : « pourquoi ma commande fournisseur / ma facture
# fournisseur rattachee a une affaire n'apparait-elle pas ? »
#
# Le script ne fait AUCUN update / delete / alter : uniquement des select et des
# lectures de catalogue. Il affiche, table par table :
#
#   1. la colonne ID_AFFAIRE existe-t-elle (stockage) ?
#   2. combien de lignes portent une affaire, aucune affaire, une affaire
#      inexistante (lecture) ?
#   3. pour une affaire donnee, combien de lignes de chaque onglet de
#      l'historique seraient visibles avec le filtre direct, et combien avec le
#      filtre via le document parent (le « fieldLink » de
#      ListeHistoriquePanel) ?
#   4. les tables de lignes qui portent leur propre ID_AFFAIRE et dont les
#      lignes sans affaire de ligne sont donc invisibles ;
#   5. la liste des corrections a appliquer.
#
# Usage (base PostgreSQL reelle) :
#   sh scripts/diagnostic-affaire-fournisseur.sh --host 127.0.0.1 --port 5433 \
#      --db OpenConcerto --user openconcerto --schema OpenConcerto42
#   PGPASSWORD=... sh scripts/diagnostic-affaire-fournisseur.sh ...
#
# Usage (demonstration sans PostgreSQL, moteur pglite) :
#   sh scripts/diagnostic-affaire-fournisseur.sh --pglite
#   sh scripts/diagnostic-affaire-fournisseur.sh --pglite --migre
#
# Options : --host --port --db --user --password --schema --affaire
#           --pglite (base de demonstration)
#           --migre  (applique la migration avant le diagnostic, pour voir
#                     l'etat apres correctif)
#
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

HOST=127.0.0.1
PORT=5433
DB=OpenConcerto
USER_NAME=openconcerto
PASSWORD=${PGPASSWORD:-}
SCHEMA=OpenConcerto42
AFFAIRE=0
PGLITE=0
MIGRE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --host) HOST=$2; shift 2 ;;
        --port) PORT=$2; shift 2 ;;
        --db) DB=$2; shift 2 ;;
        --user) USER_NAME=$2; shift 2 ;;
        --password) PASSWORD=$2; shift 2 ;;
        --schema) SCHEMA=$2; shift 2 ;;
        --affaire) AFFAIRE=$2; shift 2 ;;
        --pglite) PGLITE=1; shift ;;
        --migre) MIGRE=1; shift ;;
        -h|--help) sed -n '2,42p' "$0"; exit 0 ;;
        *) echo "option inconnue : $1" >&2; exit 2 ;;
    esac
done

WORK_DIR=$(mktemp -d)
STMT_DIR="$WORK_DIR/statements"
mkdir -p "$STMT_DIR"
trap 'rm -rf "$WORK_DIR"' EXIT

if [ "$PGLITE" -eq 1 ]; then
    if [ ! -d "$ROOT_DIR/node_modules/@electric-sql/pglite" ]; then
        (cd "$ROOT_DIR" && npm install --silent)
    fi
    mkdir -p "$WORK_DIR/bin"
    cat > "$WORK_DIR/bin/psql" <<EOF
#!/usr/bin/env bash
exec node "$ROOT_DIR/tests/sql/pglite-psql.mjs" "\$@"
EOF
    chmod +x "$WORK_DIR/bin/psql"
    PATH="$WORK_DIR/bin:$PATH"
    export PGLITE_DIR="$WORK_DIR/pglite"
    rm -rf "$PGLITE_DIR"
    psql -X -q -v ON_ERROR_STOP=1 -f "$ROOT_DIR/tests/sql/fixture-affaire-fournisseur.sql" > /dev/null
    if [ "$MIGRE" -eq 1 ]; then
        sed "s/__SCHEMA__/$SCHEMA/g" "$ROOT_DIR/tests/sql/migration-affaire-fournisseur.sql" > "$WORK_DIR/migration.sql"
        psql -X -q -v ON_ERROR_STOP=1 -f "$WORK_DIR/migration.sql" > /dev/null
        # Demonstration : on simule la saisie de l'affaire par l'utilisateur sur
        # la commande fournisseur (ecriture uniquement dans la base jetable).
        psql -X -q -v ON_ERROR_STOP=1 -c "update \"$SCHEMA\".\"COMMANDE\" set \"ID_AFFAIRE\" = 330 where \"ID\" = 100" > /dev/null
        echo "(mode pglite : base de demonstration + migration du module, schéma $SCHEMA)"
    else
        echo "(mode pglite : base de demonstration « installation existante », schéma $SCHEMA)"
    fi
    CONN=""
    [ "$AFFAIRE" -eq 0 ] && AFFAIRE=330
else
    CONN="-h $HOST -p $PORT -U $USER_NAME -d $DB"
    if [ -n "$PASSWORD" ]; then
        PGPASSWORD=$PASSWORD
        export PGPASSWORD
    fi
fi

# --- petits utilitaires ------------------------------------------------------
STMT_INDEX=0
add_stmt() {
    STMT_INDEX=$((STMT_INDEX + 1))
    number=$(printf '%03d' "$STMT_INDEX")
    cat > "$STMT_DIR/$number.sql"
}

scalar() {
    psql $CONN -X -A -t -c "$1" 2>/dev/null || echo 0
}

has_table() {
    value=$(scalar "select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = '$SCHEMA' and c.relname = '$1'")
    [ "${value:-0}" -gt 0 ]
}

has_field() {
    value=$(scalar "select count(*) from information_schema.columns where table_schema = '$SCHEMA' and table_name = '$1' and column_name = 'ID_AFFAIRE'")
    [ "${value:-0}" -gt 0 ]
}

run_statements() {
    for file in "$STMT_DIR"/*.sql; do
        [ -f "$file" ] || continue
        psql $CONN -X -v ON_ERROR_STOP=1 -c "$(cat "$file")"
    done
}

if [ "$AFFAIRE" -eq 0 ]; then
    AFFAIRE=$(scalar "select coalesce(min(\"ID\"), 0) from \"$SCHEMA\".\"AFFAIRE\" where \"ID\" > 1")
    AFFAIRE=${AFFAIRE:-0}
fi

echo
echo "================ DIAGNOSTIC AFFAIRE / DOCUMENTS FOURNISSEURS ================"
echo "schéma : $SCHEMA    affaire analysée : $AFFAIRE"
echo

# --- 0. disponibilité des tables -------------------------------------------
add_stmt <<SQL
select t."Table" as "Table",
       case when exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                         where n.nspname = '$SCHEMA' and c.relname = t."Table")
            then 'oui' else 'absente' end as "Table présente",
       case when exists (select 1 from information_schema.columns c
                         where c.table_schema = '$SCHEMA' and c.table_name = t."Table" and c.column_name = 'ID_AFFAIRE')
            then 'oui' else 'NON' end as "Colonne ID_AFFAIRE"
from (values ('DEVIS'), ('COMMANDE_CLIENT'), ('SAISIE_VENTE_FACTURE'), ('AVOIR_CLIENT'),
             ('BON_DE_LIVRAISON'), ('DEMANDE_PRIX'), ('BON_RECEPTION'), ('COMMANDE'),
             ('FACTURE_FOURNISSEUR'), ('SAISIE_ACHAT'), ('AVOIR_FOURNISSEUR'),
             ('DEMANDE_ACHAT_ELEMENT')) as t("Table");
SQL

# --- 1. etat des donnees, table par table ----------------------------------
for TABLE in DEVIS COMMANDE_CLIENT SAISIE_VENTE_FACTURE AVOIR_CLIENT BON_DE_LIVRAISON DEMANDE_PRIX BON_RECEPTION COMMANDE FACTURE_FOURNISSEUR SAISIE_ACHAT AVOIR_FOURNISSEUR DEMANDE_ACHAT_ELEMENT; do
    has_table "$TABLE" || continue
    if ! has_field "$TABLE"; then
        add_stmt <<SQL
select '$TABLE' as "Table de documents",
       'COLONNE ABSENTE : l affaire ne peut pas etre enregistree ni affichee' as "Etat";
SQL
        continue
    fi
    add_stmt <<SQL
select '$TABLE' as "Table de documents",
       count(*) as "Lignes",
       count(*) filter (where t."ID_AFFAIRE" = $AFFAIRE) as "Affaire analysée",
       count(*) filter (where t."ID_AFFAIRE" is null) as "Sans affaire",
       count(*) filter (where t."ID_AFFAIRE" = 1) as "Affaire indéfinie",
       count(*) filter (where t."ID_AFFAIRE" > 1
                          and not exists (select 1 from "$SCHEMA"."AFFAIRE" a where a."ID" = t."ID_AFFAIRE")) as "Affaire inexistante"
from "$SCHEMA"."$TABLE" t;
SQL
done

# --- 2. tables de lignes : que verrait l'historique ? ----------------------
for PAIR in "COMMANDE_ELEMENT:COMMANDE:ID_COMMANDE" "BON_RECEPTION_ELEMENT:BON_RECEPTION:ID_BON_RECEPTION"; do
    CHILD=${PAIR%%:*}
    REST=${PAIR#*:}
    PARENT=${REST%%:*}
    FIELD=${REST#*:}
    has_table "$CHILD" || continue
    has_table "$PARENT" || continue
    has_field "$PARENT" || continue
    if has_field "$CHILD"; then
        add_stmt <<SQL
select '$CHILD' as "Table de lignes",
       count(*) as "Lignes des documents $AFFAIRE",
       count(*) filter (where t."ID_AFFAIRE" = $AFFAIRE) as "Visibles (filtre direct)",
       count(*) filter (where t."ID_AFFAIRE" is null) as "CACHEES (affaire de ligne vide)"
from "$SCHEMA"."$CHILD" t
where t."$FIELD" in (select p."ID" from "$SCHEMA"."$PARENT" p where p."ID_AFFAIRE" = $AFFAIRE);
SQL
    else
        add_stmt <<SQL
select '$CHILD' as "Table de lignes",
       'filtre via $PARENT : OK (pas de colonne de ligne)' as "Mode";
SQL
    fi
done

# --- 3. la commande / facture fournisseur de l'affaire --------------------
for TABLE in COMMANDE FACTURE_FOURNISSEUR SAISIE_ACHAT AVOIR_FOURNISSEUR; do
    has_table "$TABLE" || continue
    if has_field "$TABLE"; then
        add_stmt <<SQL
select '$TABLE' as "Onglet historique", t."ID" as "ID", t."NUMERO" as "Numéro",
       a."NUMERO" as "Affaire", t."ID_AFFAIRE" as "ID_AFFAIRE"
from "$SCHEMA"."$TABLE" t
         left join "$SCHEMA"."AFFAIRE" a on a."ID" = t."ID_AFFAIRE"
where t."ID_AFFAIRE" is not null
order by t."ID";
SQL
    fi
done

run_statements

# --- 4. synthese ----------------------------------------------------------
echo
echo "================ CORRECTIONS =============================================="
MANQUANTES=""
for TABLE in DEVIS COMMANDE_CLIENT SAISIE_VENTE_FACTURE AVOIR_CLIENT BON_DE_LIVRAISON DEMANDE_PRIX BON_RECEPTION COMMANDE FACTURE_FOURNISSEUR SAISIE_ACHAT AVOIR_FOURNISSEUR DEMANDE_ACHAT_ELEMENT; do
    has_table "$TABLE" || continue
    if ! has_field "$TABLE"; then
        MANQUANTES="$MANQUANTES $TABLE"
    fi
done
if [ -n "$MANQUANTES" ]; then
    echo "1) colonne ID_AFFAIRE absente sur :$MANQUANTES"
    echo "   -> corriger avec : sed 's/__SCHEMA__/$SCHEMA/g' tests/sql/migration-affaire-fournisseur.sql | psql ..."
    echo "   -> le module l'ajoute aussi tout seul au prochain demarrage du client (Module.ensureAffairColumns)."
else
    echo "1) toutes les colonnes ID_AFFAIRE existent."
fi
for PAIR in "COMMANDE_ELEMENT:COMMANDE:ID_COMMANDE" "BON_RECEPTION_ELEMENT:BON_RECEPTION:ID_BON_RECEPTION"; do
    CHILD=${PAIR%%:*}
    REST=${PAIR#*:}
    PARENT=${REST%%:*}
    FIELD=${REST#*:}
    has_table "$CHILD" || continue
    has_field "$CHILD" || continue
    has_field "$PARENT" || continue
    CACHEES=$(scalar "select count(*) from \"$SCHEMA\".\"$CHILD\" t where t.\"ID_AFFAIRE\" is null and t.\"$FIELD\" in (select p.\"ID\" from \"$SCHEMA\".\"$PARENT\" p where p.\"ID_AFFAIRE\" = $AFFAIRE)")
    if [ "${CACHEES:-0}" -gt 0 ]; then
        echo "2) $CHILD : $CACHEES ligne(s) sans affaire de ligne invisibles en filtre direct."
        echo "   -> depuis ce correctif le module filtre ces lignes via $PARENT (aucune ligne cachée)."
    fi
done
echo "3) les documents rattaches a une affaire supprimee restent invisibles :"
scalar "select count(*) from \"$SCHEMA\".\"AFFAIRE\"" > /dev/null
for TABLE in COMMANDE FACTURE_FOURNISSEUR; do
    has_table "$TABLE" || continue
    has_field "$TABLE" || continue
    ORPHELINES=$(scalar "select count(*) from \"$SCHEMA\".\"$TABLE\" t where t.\"ID_AFFAIRE\" > 1 and not exists (select 1 from \"$SCHEMA\".\"AFFAIRE\" a where a.\"ID\" = t.\"ID_AFFAIRE\")")
    [ "${ORPHELINES:-0}" -gt 0 ] && echo "   - $TABLE : $ORPHELINES ligne(s) pointant vers une affaire inexistante"
done
echo
echo "Diagnostic terminé (aucune écriture effectuée)."
