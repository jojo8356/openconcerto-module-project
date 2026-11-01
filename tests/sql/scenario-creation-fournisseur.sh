#!/usr/bin/env sh
#
# Scenario « creation et modification d'une commande / facture fournisseur ».
#
# Ce script rejoue, en SQL sur une vraie base PostgreSQL (pglite), exactement ce
# que fait l'utilisateur dans l'ERP :
#
#   1. il cree une affaire ;
#   2. il saisit une COMMANDE FOURNISSEUR rattachee a cette affaire
#      (en-tete + lignes, comme l'ecran de saisie) ;
#   3. il transfere cette commande en FACTURE FOURNISSEUR rattachee a la meme
#      affaire (comme le fait SupplierOrderToInvoiceSQLInjector) ;
#   4. il modifie l'affaire d'une facture / d'une commande deja enregistree
#      (action « Modifier » de l'historique des affaires) ;
#   5. il verifie, a chaque etape, que le document APPARAIT dans l'historique de
#      l'affaire, avec le bon filtre et la bonne colonne « Affaire ».
#
# La base de depart est l'etat « installation existante » du client
# (tests/sql/fixture-affaire-fournisseur.sql) migre par le module
# (tests/sql/migration-affaire-fournisseur.sql) : c'est le cas ou l'affaire ne
# s'affichait pas. Le scenario prouve donc le correctif, et pas seulement le
# schema theorique.
#
# La derniere partie execute UNE REQUETE PAR ONGLET de l'historique, dans
# l'ordre ou ProjectHistory les enregistre : c'est la reproduction de la boucle
# de ListeHistoriquePanel, celle qui levait une exception des qu'une table
# n'avait pas sa colonne (et laissait donc tous les onglets suivants non
# filtres, donc vides).
#
# Usage :
#   sh tests/sql/scenario-creation-fournisseur.sh
#   WORK_DIR=/tmp/essai sh tests/sql/scenario-creation-fournisseur.sh
#
#   SANS_MIGRATION=1 sh tests/sql/scenario-creation-fournisseur.sh
#       Ne joue PAS la migration du module : reproduit la base du client avant
#       correctif. Le scenario doit alors echouer des la saisie de la commande
#       (colonne ID_AFFAIRE absente). C'est la mutation verifiee par
#       scripts/test-mutations-affaire.sh : un test qui ne peut pas echouer ne
#       prouve rien.
#
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
WORK_DIR=${WORK_DIR:-$(mktemp -d)}
DATA_DIR="$WORK_DIR/pglite"
BIN_DIR="$WORK_DIR/bin"
PSQL="$BIN_DIR/psql"
SCHEMA=OpenConcerto42

# Affaire creee par le scenario (les identifiants 330/331 viennent de la base
# de depart et servent aux comparaisons).
AFFAIRE=1000
AFFAIRE_CLOSE=331

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

# Verifie une valeur deja calculee (nombre de lignes d'un onglet, etc.).
check_value() {
    description=$1
    expected=$2
    actual=$3
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

# Filtre d'historique direct : l'onglet porte ID_AFFAIRE.
# Le second membre reproduit la regle « affaire reelle » du module
# (AffairLinkSupport.isRealAffair) : la ligne technique 1 n'est jamais
# selectionnable. On garde la comparaison dans le predicat pour ne pas perdre
# les lignes dont l'affaire est vide (NULL <> 1 n'est pas vrai).
direct_predicate() {
    printf '%s."ID_AFFAIRE" = %s and %s."ID_AFFAIRE" <> 1' "$1" "$2" "$1"
}

# Filtre d'historique via le document parent (fieldLink de
# ListeHistoriquePanel / AffairLinkSupport.ParentLink).
parent_predicate() {
    printf '%s."%s" in (select p."ID" from "%s"."%s" p where p."ID_AFFAIRE" = %s and p."ID_AFFAIRE" <> 1)' "$1" "$2" "$SCHEMA" "$3" "$4"
}

# Nombre de lignes visibles dans un onglet d'historique dont la table porte
# elle-meme l'affaire. La sous-requete sur AFFAIRE reproduit la condition
# « affaire reelle » : un document qui pointe vers une affaire supprimee est
# exclu au lieu de faire echouer la requete (cas de la facture fournisseur 201
# de la base de depart).
tab_count_direct() {
    q "select count(*) from \"$SCHEMA\".\"$1\" t
         where ($(direct_predicate t $2))
           and exists (select 1 from \"$SCHEMA\".\"AFFAIRE\" a where a.\"ID\" = t.\"ID_AFFAIRE\")"
}

# Nombre de lignes visibles dans un onglet de lignes : le filtre porte sur le
# document parent, qui est deja verifie par la sous-requete de
# parent_predicate().
tab_count_parent() {
    q "select count(*) from \"$SCHEMA\".\"$1\" t
         where ($(parent_predicate t "$2" "$3" "$4"))"
}

# Reproduit l'action « Modifier » : ecrit l'affaire sur un document existant et
# renvoie le nombre de lignes reellement modifiees (le document touche, et pas
# une copie ni zero ligne).
update_affair() {
    q "with u as (update \"$SCHEMA\".\"$1\" set \"ID_AFFAIRE\" = $3 where \"ID\" = $2 returning \"ID\") select count(*) from u"
}

check_update() {
    description=$1
    expected=$2
    actual=$(update_affair "$3" "$4" "$5" 2>&1) || actual="ERREUR: $actual"
    if [ "$actual" = "$expected" ]; then
        ok "$description"
    else
        ko "$description (attendu : '$expected', obtenu : '$actual')"
    fi
}

echo "== 1. base de depart : installation existante + migration du module =="
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

"$PSQL" -X -v ON_ERROR_STOP=1 -f "$ROOT_DIR/tests/sql/fixture-affaire-fournisseur.sql" > /dev/null
sed "s/__SCHEMA__/$SCHEMA/g" "$ROOT_DIR/tests/sql/migration-affaire-fournisseur.sql" > "$WORK_DIR/migration.sql"
if [ "${SANS_MIGRATION:-0}" = "1" ]; then
    echo "!! SANS_MIGRATION=1 : migration volontairement non jouee"
    echo "!! (reproduction du symptome : la colonne ID_AFFAIRE n'existe pas)"
else
    "$PSQL" -X -v ON_ERROR_STOP=1 -f "$WORK_DIR/migration.sql" > /dev/null
fi

check "les 4 tables de documents fournisseurs portent ID_AFFAIRE" "4" \
    "select count(*) from information_schema.columns where table_schema = '$SCHEMA' and column_name = 'ID_AFFAIRE' and table_name in ('COMMANDE','FACTURE_FOURNISSEUR','SAISIE_ACHAT','AVOIR_FOURNISSEUR')"
check "la cle etrangere de COMMANDE vers AFFAIRE est installee mais non validee (donnees anciennes tolerees)" "f" \
    "select convalidated from pg_constraint cons join pg_class c on c.oid = cons.conrelid join pg_namespace n on n.oid = c.relnamespace where n.nspname = '$SCHEMA' and c.relname = 'COMMANDE' and cons.conname = 'COMMANDE_ID_AFFAIRE_fkey'"
check "la facture fournisseur 201 pointe deja vers une affaire inexistante (999)" "1" \
    "select count(*) from \"$SCHEMA\".\"FACTURE_FOURNISSEUR\" t where t.\"ID_AFFAIRE\" = 999 and not exists (select 1 from \"$SCHEMA\".\"AFFAIRE\" a where a.\"ID\" = 999)"

echo "== 2. l'utilisateur cree une affaire =="
q "insert into \"$SCHEMA\".\"AFFAIRE\" (\"ID\",\"NUMERO\",\"NOM\",\"DATE\",\"ID_CLIENT\",\"ID_ETAT_AFFAIRE\")
   values ($AFFAIRE,'AFF-1000','Affaire creee par le scenario','2026-10-26',1,3)" > /dev/null
check "l'affaire 1000 existe et est ouverte" "AFF-1000|3" \
    "select \"NUMERO\" || '|' || \"ID_ETAT_AFFAIRE\" from \"$SCHEMA\".\"AFFAIRE\" where \"ID\" = $AFFAIRE"

echo "== 3. l'utilisateur saisit une commande fournisseur sur cette affaire =="
cat > "$WORK_DIR/commande.sql" <<SQL
-- Ecran « Commande fournisseur » : l'en-tete est enregistre avec l'affaire
-- saisie (putAdditionalField COMMANDE / ID_AFFAIRE), puis les lignes.
insert into "$SCHEMA"."COMMANDE" ("ID","NUMERO","NOM","DATE","ID_FOURNISSEUR","T_HT","T_TTC","EN_COURS","INFOS","ID_AFFAIRE")
values (2000,'CMD-2000','Commande creee ecran','2026-10-26',1,60000,72000,true,'Saisie sur affaire',$AFFAIRE);
insert into "$SCHEMA"."COMMANDE_ELEMENT" ("ID","ID_COMMANDE","DESIGNATION","QTE","T_PA_HT","ID_AFFAIRE") values
    (3001,2000,'Article ecran 1',1,100.00,null),
    (3002,2000,'Article ecran 2',2,150.00,null),
    (3003,2000,'Article ecran 3',1,200.00,null);
SQL
"$PSQL" -X -v ON_ERROR_STOP=1 -f "$WORK_DIR/commande.sql" > /dev/null

check "la commande fournisseur enregistre bien l'affaire 1000" "$AFFAIRE" \
    "select \"ID_AFFAIRE\" from \"$SCHEMA\".\"COMMANDE\" where \"ID\" = 2000"
check "le total HT de la commande correspond a ses lignes (quantite x prix)" "60000" \
    "select round(sum(\"QTE\" * \"T_PA_HT\") * 100)::bigint from \"$SCHEMA\".\"COMMANDE_ELEMENT\" where \"ID_COMMANDE\" = 2000"
check "onglet « Commandes fournisseurs » : la commande apparait sous l'affaire 1000" "1" \
    "select count(*) from \"$SCHEMA\".\"COMMANDE\" t where t.\"NUMERO\" = 'CMD-2000' and $(direct_predicate t $AFFAIRE)"
check_value "onglet « Commandes fournisseurs » : 1 seule commande pour l'affaire 1000" "1" \
    "$(tab_count_direct COMMANDE "$AFFAIRE")"
check "colonne « Affaire » de la liste des commandes fournisseurs : AFF-1000" "AFF-1000" \
    "select a.\"NUMERO\" from \"$SCHEMA\".\"COMMANDE\" t left join \"$SCHEMA\".\"AFFAIRE\" a on a.\"ID\" = t.\"ID_AFFAIRE\" where t.\"ID\" = 2000"
check "onglet « Articles commandes » : les 3 lignes apparaissent via la commande" "3" \
    "select count(*) from \"$SCHEMA\".\"COMMANDE_ELEMENT\" t where $(parent_predicate t ID_COMMANDE COMMANDE $AFFAIRE) and t.\"ID_COMMANDE\" = 2000"
check "les lignes n'ont pas d'affaire propre (c'est le document qui porte l'affaire)" "3" \
    "select count(*) from \"$SCHEMA\".\"COMMANDE_ELEMENT\" where \"ID_COMMANDE\" = 2000 and \"ID_AFFAIRE\" is null"
check "filtre direct sur la ligne : les 3 lignes seraient invisibles" "0" \
    "select count(*) from \"$SCHEMA\".\"COMMANDE_ELEMENT\" t where t.\"ID_COMMANDE\" = 2000 and $(direct_predicate t $AFFAIRE)"
check "la commande n'apparait pas sous une autre affaire" "0" \
    "select count(*) from \"$SCHEMA\".\"COMMANDE\" t where t.\"ID\" = 2000 and $(direct_predicate t $AFFAIRE_CLOSE)"

echo "== 4. l'utilisateur transfere la commande en facture fournisseur =="
# Reproduit SupplierOrderToInvoiceSQLInjector : la facture reprend l'affaire de
# la commande, et ses lignes pointent vers les lignes de la commande.
cat > "$WORK_DIR/facture.sql" <<SQL
insert into "$SCHEMA"."FACTURE_FOURNISSEUR" ("ID","NUMERO","NOM","DATE","ID_FOURNISSEUR","T_HT","T_TTC","INFOS","ID_AFFAIRE")
select 2100,'FF-2100','Facture transferee','2026-10-26',c."ID_FOURNISSEUR",c."T_HT",c."T_TTC",'Transfert commande CMD-2000',c."ID_AFFAIRE"
from "$SCHEMA"."COMMANDE" c where c."ID" = 2000;
insert into "$SCHEMA"."FACTURE_FOURNISSEUR_ELEMENT" ("ID","ID_FACTURE_FOURNISSEUR","ID_COMMANDE_ELEMENT","DESIGNATION","T_PA_HT")
select 4000 + e."ID" % 1000,2100,e."ID",e."DESIGNATION",e."T_PA_HT"
from "$SCHEMA"."COMMANDE_ELEMENT" e where e."ID_COMMANDE" = 2000 order by e."ID";
SQL
"$PSQL" -X -v ON_ERROR_STOP=1 -f "$WORK_DIR/facture.sql" > /dev/null

check "la facture fournisseur herite de l'affaire de la commande" "$AFFAIRE" \
    "select \"ID_AFFAIRE\" from \"$SCHEMA\".\"FACTURE_FOURNISSEUR\" where \"ID\" = 2100"
check "onglet « Factures fournisseurs » : la facture apparait sous l'affaire 1000" "1" \
    "select count(*) from \"$SCHEMA\".\"FACTURE_FOURNISSEUR\" t where t.\"ID\" = 2100 and $(direct_predicate t $AFFAIRE)"
check "colonne « Affaire » de la liste des factures fournisseurs : AFF-1000" "AFF-1000" \
    "select a.\"NUMERO\" from \"$SCHEMA\".\"FACTURE_FOURNISSEUR\" t left join \"$SCHEMA\".\"AFFAIRE\" a on a.\"ID\" = t.\"ID_AFFAIRE\" where t.\"ID\" = 2100"
check "les 3 lignes de la facture sont creees" "3" \
    "select count(*) from \"$SCHEMA\".\"FACTURE_FOURNISSEUR_ELEMENT\" where \"ID_FACTURE_FOURNISSEUR\" = 2100"
check "les lignes de la facture pointent vers les lignes de la commande (rattachement complet)" "3" \
    "select count(*) from \"$SCHEMA\".\"FACTURE_FOURNISSEUR_ELEMENT\" fe join \"$SCHEMA\".\"COMMANDE_ELEMENT\" ce on ce.\"ID\" = fe.\"ID_COMMANDE_ELEMENT\" join \"$SCHEMA\".\"COMMANDE\" c on c.\"ID\" = ce.\"ID_COMMANDE\" where fe.\"ID_FACTURE_FOURNISSEUR\" = 2100 and c.\"ID\" = 2000"
check "aucune ligne de facture orpheline (sans ligne de commande)" "0" \
    "select count(*) from \"$SCHEMA\".\"FACTURE_FOURNISSEUR_ELEMENT\" fe left join \"$SCHEMA\".\"COMMANDE_ELEMENT\" ce on ce.\"ID\" = fe.\"ID_COMMANDE_ELEMENT\" where fe.\"ID_FACTURE_FOURNISSEUR\" = 2100 and ce.\"ID\" is null"
check "les prix des lignes de facture sont ceux des lignes de commande" "0.00" \
    "select to_char((select sum(\"T_PA_HT\") from \"$SCHEMA\".\"FACTURE_FOURNISSEUR_ELEMENT\" where \"ID_FACTURE_FOURNISSEUR\" = 2100) - (select sum(\"T_PA_HT\") from \"$SCHEMA\".\"COMMANDE_ELEMENT\" where \"ID_COMMANDE\" = 2000), 'FM999999990.00')"
check "bilan simple de l'affaire : commande et facture au meme montant" "0" \
    "select (select sum(\"T_HT\") from \"$SCHEMA\".\"COMMANDE\" where \"ID\" = 2000) - (select sum(\"T_HT\") from \"$SCHEMA\".\"FACTURE_FOURNISSEUR\" where \"ID\" = 2100)"

echo "== 5. un document cree AVANT le correctif peut enfin recevoir une affaire =="
# La commande 100 existe dans la base de depart, sans colonne ID_AFFAIRE : c'est
# le document que l'utilisateur ne pouvait pas rattacher.
check "la commande 100 n'avait aucune affaire" "0" \
    "select count(*) from \"$SCHEMA\".\"COMMANDE\" where \"ID\" = 100 and \"ID_AFFAIRE\" is not null"
check_update "l'action « Modifier » touche bien la commande 100" "1" COMMANDE 100 "$AFFAIRE"
check_value "onglet « Commandes fournisseurs » : 2 commandes pour l'affaire 1000" "2" \
    "$(tab_count_direct COMMANDE "$AFFAIRE")"
check_value "onglet « Articles commandes » : 7 lignes (3 nouvelles + 4 de la commande 100)" "7" \
    "$(tab_count_parent COMMANDE_ELEMENT ID_COMMANDE COMMANDE "$AFFAIRE")"

echo "== 6. modification de l'affaire d'une facture fournisseur deja enregistree =="
# Cas exact du symptome : une facture saisie SANS affaire, que l'on rattache
# ensuite (action « Modifier » de l'historique ou de la liste).
q "insert into \"$SCHEMA\".\"FACTURE_FOURNISSEUR\" (\"ID\",\"NUMERO\",\"NOM\",\"DATE\",\"ID_FOURNISSEUR\",\"T_HT\",\"T_TTC\",\"INFOS\",\"ID_AFFAIRE\")
   values (2101,'FF-2101','Facture sans affaire','2026-10-26',1,12000,14400,'Saisie sans affaire',null)" > /dev/null
check "la facture sans affaire n'apparait dans aucun onglet d'affaire" "0" \
    "select count(*) from \"$SCHEMA\".\"FACTURE_FOURNISSEUR\" t where t.\"ID\" = 2101 and $(direct_predicate t $AFFAIRE)"
check_value "seule la facture 2100 est rattachee a l'affaire 1000 pour l'instant" "1" \
    "$(tab_count_direct FACTURE_FOURNISSEUR "$AFFAIRE")"
check_update "l'action « Modifier » touche bien la facture 2101" "1" FACTURE_FOURNISSEUR 2101 "$AFFAIRE"
check "apres modification, l'affaire est reellement enregistree" "$AFFAIRE" \
    "select \"ID_AFFAIRE\" from \"$SCHEMA\".\"FACTURE_FOURNISSEUR\" where \"ID\" = 2101"
check "apres modification, la facture apparait sous l'affaire 1000" "1" \
    "select count(*) from \"$SCHEMA\".\"FACTURE_FOURNISSEUR\" t where t.\"ID\" = 2101 and $(direct_predicate t $AFFAIRE)"
check_value "onglet « Factures fournisseurs » : 2 factures pour l'affaire 1000" "2" \
    "$(tab_count_direct FACTURE_FOURNISSEUR "$AFFAIRE")"
check "la modification ne cree pas de doublon" "1" \
    "select count(*) from \"$SCHEMA\".\"FACTURE_FOURNISSEUR\" where \"NUMERO\" = 'FF-2101'"

echo "== 7. changer une facture d'affaire (et la retirer) =="
check_update "deplacement de la facture 2100 vers l'affaire close 331" "1" FACTURE_FOURNISSEUR 2100 "$AFFAIRE_CLOSE"
check_value "elle quitte l'affaire 1000" "1" \
    "$(tab_count_direct FACTURE_FOURNISSEUR "$AFFAIRE")"
check_value "elle apparait sous l'affaire 331" "1" \
    "$(tab_count_direct FACTURE_FOURNISSEUR "$AFFAIRE_CLOSE")"
q "update \"$SCHEMA\".\"FACTURE_FOURNISSEUR\" set \"ID_AFFAIRE\" = $AFFAIRE where \"ID\" = 2100" > /dev/null
check_value "retour sous l'affaire 1000" "2" \
    "$(tab_count_direct FACTURE_FOURNISSEUR "$AFFAIRE")"
q "update \"$SCHEMA\".\"FACTURE_FOURNISSEUR\" set \"ID_AFFAIRE\" = null where \"ID\" = 2101" > /dev/null
check_value "retirer l'affaire fait disparaitre la facture de l'historique" "1" \
    "$(tab_count_direct FACTURE_FOURNISSEUR "$AFFAIRE")"
q "update \"$SCHEMA\".\"FACTURE_FOURNISSEUR\" set \"ID_AFFAIRE\" = $AFFAIRE where \"ID\" = 2101" > /dev/null

echo "== 8. meme chose sur une commande fournisseur =="
q "insert into \"$SCHEMA\".\"COMMANDE\" (\"ID\",\"NUMERO\",\"NOM\",\"DATE\",\"ID_FOURNISSEUR\",\"T_HT\",\"T_TTC\",\"EN_COURS\",\"INFOS\")
   values (2200,'CMD-2200','Commande sans affaire','2026-10-26',1,15000,18000,true,'Saisie sans affaire')" > /dev/null
q "insert into \"$SCHEMA\".\"COMMANDE_ELEMENT\" (\"ID\",\"ID_COMMANDE\",\"DESIGNATION\",\"QTE\",\"T_PA_HT\")
   values (3101,2200,'Article 2200',1,150.00)" > /dev/null
check "la commande sans affaire n'apparait pas dans l'historique" "0" \
    "select count(*) from \"$SCHEMA\".\"COMMANDE\" t where t.\"ID\" = 2200 and $(direct_predicate t $AFFAIRE)"
check_update "l'action « Modifier » touche bien la commande 2200" "1" COMMANDE 2200 "$AFFAIRE"
check_value "onglet « Commandes fournisseurs » : 3 commandes pour l'affaire 1000" "3" \
    "$(tab_count_direct COMMANDE "$AFFAIRE")"
check_value "onglet « Articles commandes » : 8 lignes pour l'affaire 1000" "8" \
    "$(tab_count_parent COMMANDE_ELEMENT ID_COMMANDE COMMANDE "$AFFAIRE")"
check "sa ligne est visible via la commande, sans affaire de ligne" "1" \
    "select count(*) from \"$SCHEMA\".\"COMMANDE_ELEMENT\" t where t.\"ID\" = 3101 and $(parent_predicate t ID_COMMANDE COMMANDE $AFFAIRE)"
check "la ligne 1004 garde son affaire 331 mais reste visible via sa commande" "1" \
    "select count(*) from \"$SCHEMA\".\"COMMANDE_ELEMENT\" t where t.\"ID\" = 1004 and $(parent_predicate t ID_COMMANDE COMMANDE $AFFAIRE)"

echo "== 9. garde-fous : affaire indefinie, affaire inexistante =="
q "insert into \"$SCHEMA\".\"FACTURE_FOURNISSEUR\" (\"ID\",\"NUMERO\",\"NOM\",\"DATE\",\"ID_FOURNISSEUR\",\"T_HT\",\"T_TTC\",\"INFOS\",\"ID_AFFAIRE\")
   values (2102,'FF-2102','Facture affaire indefinie','2026-10-26',1,5000,6000,'Affaire 1',1)" > /dev/null
check "l'affaire indefinie (1) est bien stockee" "1" \
    "select \"ID_AFFAIRE\" from \"$SCHEMA\".\"FACTURE_FOURNISSEUR\" where \"ID\" = 2102"
check_value "mais elle n'est jamais affichee dans l'historique d'une affaire" "0" \
    "$(tab_count_direct FACTURE_FOURNISSEUR 1)"
check_value "onglet « Factures fournisseurs » : toujours 2 factures sous l'affaire 1000" "2" \
    "$(tab_count_direct FACTURE_FOURNISSEUR "$AFFAIRE")"
expect_error "une nouvelle ecriture vers une affaire inexistante est refusee" "foreign key" \
    "update \"$SCHEMA\".\"FACTURE_FOURNISSEUR\" set \"ID_AFFAIRE\" = 999999 where \"ID\" = 2101"
check "la valeur refusee n'a pas ete ecrite" "$AFFAIRE" \
    "select \"ID_AFFAIRE\" from \"$SCHEMA\".\"FACTURE_FOURNISSEUR\" where \"ID\" = 2101"
check "la facture ancienne pointant vers une affaire supprimee reste toleree" "1" \
    "select count(*) from \"$SCHEMA\".\"FACTURE_FOURNISSEUR\" t where t.\"ID\" = 201"
check "et elle ne casse pas la requete de l'historique" "0" \
    "select count(*) from \"$SCHEMA\".\"FACTURE_FOURNISSEUR\" t join \"$SCHEMA\".\"AFFAIRE\" a on a.\"ID\" = t.\"ID_AFFAIRE\" where t.\"ID\" = 201"

echo "== 10. boucle des onglets de l'historique (reproduction de ListeHistoriquePanel) =="
# Chaque onglet est interroge exactement comme le fait le panneau d'historique,
# dans l'ordre de ProjectHistory. Un onglet dont la table manque doit etre
# simplement absent de la boucle (putAffairTab / planTab) ; un onglet present
# doit repondre sans erreur. C'est ce qui empechait la boucle de casser.
onglet() {
    label=$1
    table=$2
    parent_field=$3
    parent_table=$4
    if [ "$(q "select count(*) from information_schema.tables where table_schema = '$SCHEMA' and table_name = '$table'")" = "0" ]; then
        ok "onglet « $label » : table $table absente, onglet ignore sans casser la boucle"
        return
    fi
    if [ -n "$parent_field" ]; then
        predicate=$(parent_predicate t "$parent_field" "$parent_table" "$AFFAIRE")
    else
        predicate=$(direct_predicate t "$AFFAIRE")
    fi
    set +e
    out=$(q "select count(*) from \"$SCHEMA\".\"$table\" t where $predicate" 2>&1)
    code=$?
    set -e
    case $out in
        ''|*[!0-9]*)
            ko "onglet « $label » : le filtre par affaire echoue ($out)"
            ;;
        *)
            if [ "$code" -ne 0 ]; then
                ko "onglet « $label » : code $code ($out)"
            else
                ok "onglet « $label » : filtre par affaire operationnel ($out ligne(s))"
            fi
            ;;
    esac
}

onglet "Devis" DEVIS "" ""
onglet "Bons de commande" COMMANDE_CLIENT "" ""
onglet "Chiffrage" CHIFFRAGE_COMMANDE_CLIENT ID_COMMANDE_CLIENT COMMANDE_CLIENT
onglet "Factures" SAISIE_VENTE_FACTURE "" ""
onglet "Avoirs" AVOIR_CLIENT "" ""
onglet "Demandes d'achat" DEMANDE_ACHAT_ELEMENT "" ""
onglet "Demandes de prix" DEMANDE_PRIX "" ""
onglet "Bons de livraison clients" BON_DE_LIVRAISON "" ""
onglet "Commandes fournisseurs" COMMANDE "" ""
onglet "Articles commandes" COMMANDE_ELEMENT ID_COMMANDE COMMANDE
onglet "Bons de reception fournisseurs" BON_RECEPTION "" ""
onglet "Articles receptionnes" BON_RECEPTION_ELEMENT ID_BON_RECEPTION BON_RECEPTION
onglet "Achats" SAISIE_ACHAT "" ""
onglet "Factures fournisseurs" FACTURE_FOURNISSEUR "" ""
onglet "Avoirs fournisseurs" AVOIR_FOURNISSEUR "" ""

echo "== 11. etat final de l'affaire 1000 =="
check_value "3 commandes fournisseurs rattachees" "3" \
    "$(tab_count_direct COMMANDE "$AFFAIRE")"
check_value "8 lignes de commande visibles" "8" \
    "$(tab_count_parent COMMANDE_ELEMENT ID_COMMANDE COMMANDE "$AFFAIRE")"
check_value "2 factures fournisseurs rattachees" "2" \
    "$(tab_count_direct FACTURE_FOURNISSEUR "$AFFAIRE")"
check "aucun document n'a change d'identifiant (pas de doublon)" "3|2" \
    "select (select count(*) from \"$SCHEMA\".\"COMMANDE\" where \"ID_AFFAIRE\" = $AFFAIRE and \"ID\" in (100,2000,2200)) || '|' || (select count(*) from \"$SCHEMA\".\"FACTURE_FOURNISSEUR\" where \"ID_AFFAIRE\" = $AFFAIRE and \"ID\" in (2100,2101))"
check "total des commandes fournisseurs de l'affaire 1000 (1950.00)" "195000" \
    "select sum(\"T_HT\")::bigint from \"$SCHEMA\".\"COMMANDE\" t where $(direct_predicate t $AFFAIRE)"
check "total des factures fournisseurs de l'affaire 1000 (720.00)" "72000" \
    "select sum(\"T_HT\")::bigint from \"$SCHEMA\".\"FACTURE_FOURNISSEUR\" t where $(direct_predicate t $AFFAIRE)"

echo
echo "Controles : $CONTROLES | echecs : $ECHECS"
if [ "$ECHECS" -ne 0 ]; then
    echo "RESULTAT : ECHEC"
    exit 1
fi
echo "RESULTAT : OK"
