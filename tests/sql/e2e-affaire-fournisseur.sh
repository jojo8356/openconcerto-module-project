#!/usr/bin/env sh
#
# Test de bout en bout « affaire sur les documents fournisseurs ».
#
# Objectif : prouver, sur une vraie base PostgreSQL (pglite), pourquoi une
# commande fournisseur ou une facture fournisseur rattachee a une affaire
# n'apparait pas, puis verifier que le correctif la fait apparaitre.
#
# Le script enchaine les deux etats de la meme base :
#
#   1. "installation existante" (tests/sql/fixture-affaire-fournisseur.sql) :
#      la colonne ID_AFFAIRE manque sur COMMANDE / SAISIE_ACHAT /
#      AVOIR_FOURNISSEUR -> il est IMPOSSIBLE d'enregistrer l'affaire, et
#      l'onglet d'historique ne peut pas filtrer ;
#   2. apres la migration du module
#      (tests/sql/migration-affaire-fournisseur.sql) : l'affaire s'enregistre
#      et l'historique la retrouve.
#
# Chaque verification affiche OK / ECHEC ; le script sort en erreur des qu'une
# seule verification echoue.
#
# Usage :
#   sh tests/sql/e2e-affaire-fournisseur.sh
#   WORK_DIR=/tmp/essai sh tests/sql/e2e-affaire-fournisseur.sh
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

ok() {
    CONTROLES=$((CONTROLES + 1))
    printf 'OK     %s\n' "$1"
}

ko() {
    CONTROLES=$((CONTROLES + 1))
    ECHECS=$((ECHECS + 1))
    printf 'ECHEC  %s\n' "$1"
}

# psql simplifie : une requete, resultat brut.
q() {
    "$PSQL" -X -A -t -v ON_ERROR_STOP=1 -c "$1"
}

# Verifie qu'une requete renvoie exactement la valeur attendue.
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

# Predicat d'historique, tel que le construit ListeHistoriquePanel quand une
# affaire est selectionnee (voir AffairLinkSupport.buildSelectionPredicate).
direct_predicate() {
    printf '%s."ID_AFFAIRE" = %s' "$1" "$2"
}

parent_predicate() {
    # $1 = alias de la table de lignes, $2 = colonne de liaison,
    # $3 = table parente, $4 = affaire recherchee
    printf '%s."%s" in (select p."ID" from "%s"."%s" p where p."ID_AFFAIRE" = %s)' "$1" "$2" "$SCHEMA" "$3" "$4"
}

# Lignes visibles pour une affaire, avec le filtre « historique » complet :
# affaire existante, differente de la ligne technique 1.
history_count() {
    table=$1
    predicate=$2
    q "select count(*) from \"$SCHEMA\".\"$table\" t
         where ($predicate)
           and exists (select 1 from \"$SCHEMA\".\"AFFAIRE\" a where a.\"ID\" = t.\"ID_AFFAIRE\")"
}

echo "== 1. preparation de l'environnement =="
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

echo "== 2. base dans l'etat « installation existante » =="
"$PSQL" -X -v ON_ERROR_STOP=1 -f "$ROOT_DIR/tests/sql/fixture-affaire-fournisseur.sql" > /dev/null

# --- Etat des colonnes -------------------------------------------------
check "COMMANDE n'a pas encore de colonne ID_AFFAIRE" "0" \
    "select count(*) from information_schema.columns where table_schema = '$SCHEMA' and table_name = 'COMMANDE' and column_name = 'ID_AFFAIRE'"
check "FACTURE_FOURNISSEUR a deja la colonne ID_AFFAIRE" "1" \
    "select count(*) from information_schema.columns where table_schema = '$SCHEMA' and table_name = 'FACTURE_FOURNISSEUR' and column_name = 'ID_AFFAIRE'"
check "SAISIE_ACHAT n'a pas la colonne ID_AFFAIRE" "0" \
    "select count(*) from information_schema.columns where table_schema = '$SCHEMA' and table_name = 'SAISIE_ACHAT' and column_name = 'ID_AFFAIRE'"

# --- Le symptome n°1 : impossible d'enregistrer l'affaire --------------
set +e
ERREUR=$(q "update \"$SCHEMA\".\"COMMANDE\" set \"ID_AFFAIRE\" = 330 where \"ID\" = 100" 2>&1)
CODE=$?
set -e
if [ "$CODE" -ne 0 ] && echo "$ERREUR" | grep -q "ID_AFFAIRE"; then
    ok "sans la colonne, l'affaire ne peut pas etre enregistree sur la commande fournisseur"
else
    ko "l'ecriture de l'affaire aurait du echouer (code $CODE : $ERREUR)"
fi

# --- Le symptome n°2 : l'onglet ne peut pas etre filtre ----------------
check "avant migration, la facture fournisseur est bien retrouvee par l'affaire 330" "1" \
    "select count(*) from \"$SCHEMA\".\"FACTURE_FOURNISSEUR\" t where $(direct_predicate t 330)"
set +e
ERREUR=$(q "select count(*) from \"$SCHEMA\".\"COMMANDE\" t where t.\"ID_AFFAIRE\" = 330" 2>&1)
CODE=$?
set -e
if [ "$CODE" -ne 0 ] && echo "$ERREUR" | grep -q "ID_AFFAIRE"; then
    ok "sans la colonne, l'onglet « Commandes fournisseurs » ne peut pas etre filtre par affaire"
else
    ko "le filtrage de l'onglet aurait du echouer faute de colonne (code $CODE : $ERREUR)"
fi

echo "== 3. migration du module (tests/sql/migration-affaire-fournisseur.sql) =="
sed "s/__SCHEMA__/$SCHEMA/g" "$ROOT_DIR/tests/sql/migration-affaire-fournisseur.sql" > "$WORK_DIR/migration.sql"
"$PSQL" -X -v ON_ERROR_STOP=1 -f "$WORK_DIR/migration.sql" > /dev/null

check "les 12 tables de documents portent ID_AFFAIRE apres migration" "12" \
    "select count(*) from information_schema.columns where table_schema = '$SCHEMA' and column_name = 'ID_AFFAIRE' and table_name in ('DEVIS','COMMANDE_CLIENT','SAISIE_VENTE_FACTURE','AVOIR_CLIENT','BON_DE_LIVRAISON','DEMANDE_PRIX','BON_RECEPTION','COMMANDE','FACTURE_FOURNISSEUR','SAISIE_ACHAT','AVOIR_FOURNISSEUR','DEMANDE_ACHAT_ELEMENT')"
check "aucune colonne ID_AFFAIRE ajoutee sur les tables de lignes" "1" \
    "select count(*) from information_schema.columns where table_schema = '$SCHEMA' and column_name = 'ID_AFFAIRE' and table_name = 'COMMANDE_ELEMENT'"

# --- Idempotence : on rejoue la migration ------------------------------
"$PSQL" -X -v ON_ERROR_STOP=1 -f "$WORK_DIR/migration.sql" > /dev/null
check "la migration est idempotente (toujours 12 colonnes)" "12" \
    "select count(*) from information_schema.columns where table_schema = '$SCHEMA' and column_name = 'ID_AFFAIRE' and table_name in ('DEVIS','COMMANDE_CLIENT','SAISIE_VENTE_FACTURE','AVOIR_CLIENT','BON_DE_LIVRAISON','DEMANDE_PRIX','BON_RECEPTION','COMMANDE','FACTURE_FOURNISSEUR','SAISIE_ACHAT','AVOIR_FOURNISSEUR','DEMANDE_ACHAT_ELEMENT')"
check "la cle etrangere vers AFFAIRE n'est pas dupliquee" "1" \
    "select count(*) from pg_constraint cons join pg_class c on c.oid = cons.conrelid join pg_namespace n on n.oid = c.relnamespace join pg_class rc on rc.oid = cons.confrelid where n.nspname = '$SCHEMA' and c.relname = 'COMMANDE' and cons.contype = 'f' and rc.relname = 'AFFAIRE'"

echo "== 4. apres correctif : l'affaire s'enregistre et se retrouve =="
q "update \"$SCHEMA\".\"COMMANDE\" set \"ID_AFFAIRE\" = 330 where \"ID\" = 100" > /dev/null
q "update \"$SCHEMA\".\"COMMANDE\" set \"ID_AFFAIRE\" = 331 where \"ID\" = 102" > /dev/null
q "update \"$SCHEMA\".\"SAISIE_ACHAT\" set \"ID_AFFAIRE\" = 330 where \"ID\" = 300" > /dev/null
q "update \"$SCHEMA\".\"AVOIR_FOURNISSEUR\" set \"ID_AFFAIRE\" = 330 where \"ID\" = 400" > /dev/null

check "l'affaire 330 est enregistree sur la commande fournisseur" "330" \
    "select \"ID_AFFAIRE\" from \"$SCHEMA\".\"COMMANDE\" where \"ID\" = 100"
check "onglet « Commandes fournisseurs » : 1 commande pour l'affaire 330" "1" \
    "select count(*) from \"$SCHEMA\".\"COMMANDE\" t where $(direct_predicate t 330)"
check "onglet « Commandes fournisseurs » : la commande close est sous l'affaire 331" "1" \
    "select count(*) from \"$SCHEMA\".\"COMMANDE\" t where t.\"NUMERO\" = 'CMD-102' and $(direct_predicate t 331)"
check "onglet « Factures fournisseurs » : la facture 200 est sous l'affaire 330" "1" \
    "select count(*) from \"$SCHEMA\".\"FACTURE_FOURNISSEUR\" t where t.\"NUMERO\" = 'FF-200' and $(direct_predicate t 330)"
check "onglet « Achats » : l'achat 300 est sous l'affaire 330" "1" \
    "select count(*) from \"$SCHEMA\".\"SAISIE_ACHAT\" t where $(direct_predicate t 330)"
check "onglet « Avoirs fournisseurs » : l'avoir 400 est sous l'affaire 330" "1" \
    "select count(*) from \"$SCHEMA\".\"AVOIR_FOURNISSEUR\" t where $(direct_predicate t 330)"

# --- Colonne « Affaire » des listes de l'ERP ---------------------------
check "colonne « Affaire » de la liste des commandes fournisseurs" "AFF-330" \
    "select a.\"NUMERO\" from \"$SCHEMA\".\"COMMANDE\" t left join \"$SCHEMA\".\"AFFAIRE\" a on a.\"ID\" = t.\"ID_AFFAIRE\" where t.\"ID\" = 100"
check "colonne « Affaire » de la liste des factures fournisseurs" "AFF-330" \
    "select a.\"NUMERO\" from \"$SCHEMA\".\"FACTURE_FOURNISSEUR\" t left join \"$SCHEMA\".\"AFFAIRE\" a on a.\"ID\" = t.\"ID_AFFAIRE\" where t.\"ID\" = 200"

echo "== 5. cas limites =="
check "affaire indefinie (1) : aucune commande" "0" \
    "select count(*) from \"$SCHEMA\".\"COMMANDE\" t where $(direct_predicate t 1)"
check "commande sans affaire : jamais dans un onglet d'affaire" "1" \
    "select count(*) from \"$SCHEMA\".\"COMMANDE\" t where t.\"NUMERO\" = 'CMD-101' and t.\"ID_AFFAIRE\" is null"
check "facture pointant sur une affaire supprimee : exclue par la jointure AFFAIRE" "0" \
    "select count(*) from \"$SCHEMA\".\"FACTURE_FOURNISSEUR\" t left join \"$SCHEMA\".\"AFFAIRE\" a on a.\"ID\" = t.\"ID_AFFAIRE\" where t.\"ID\" = 201 and a.\"ID\" is not null"
check "affaire 331 (close) : la facture 200 n'y figure pas" "0" \
    "select count(*) from \"$SCHEMA\".\"FACTURE_FOURNISSEUR\" t where t.\"ID\" = 200 and $(direct_predicate t 331)"

echo "== 6. lignes de commande : le piege de la colonne de ligne =="
# COMMANDE_ELEMENT porte sa propre colonne ID_AFFAIRE : le module d'origine ne
# declare donc AUCUN lien parent, et l'historique filtre directement sur
# l'affaire de ligne. Les 3 lignes sans affaire de ligne deviennent invisibles
# alors que leur commande est rattachee a l'affaire 330.
check "filtre direct sur la ligne : seules les lignes ayant leur propre affaire remontent" "1" \
    "select count(*) from \"$SCHEMA\".\"COMMANDE_ELEMENT\" t where $(direct_predicate t 331)"
check "filtre direct sur l'affaire 330 : les 3 lignes de la commande 100 sont perdues" "0" \
    "select count(*) from \"$SCHEMA\".\"COMMANDE_ELEMENT\" t where $(direct_predicate t 330)"
check "filtre via le document parent : les 4 lignes de la commande 100 remontent" "4" \
    "select count(*) from \"$SCHEMA\".\"COMMANDE_ELEMENT\" t where $(parent_predicate t ID_COMMANDE COMMANDE 330)"
check "union des deux filtres : rien n'est perdu" "4" \
    "select count(*) from \"$SCHEMA\".\"COMMANDE_ELEMENT\" t where ($(direct_predicate t 330)) or ($(parent_predicate t ID_COMMANDE COMMANDE 330))"

echo
echo "Controles : $CONTROLES | echecs : $ECHECS"
if [ "$ECHECS" -ne 0 ]; then
    echo "RESULTAT : ECHEC"
    exit 1
fi
echo "RESULTAT : OK"
