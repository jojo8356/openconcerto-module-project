#!/usr/bin/env sh
#
# Tests de mutation du correctif « affaire sur les documents fournisseurs ».
#
# Un test ne vaut que s'il sait echouer. Ce script introduit volontairement des
# regressions dans une COPIE du depot, puis verifie que la suite de tests les
# detecte. Si une mutation passe inapercue, le script sort en erreur : cela
# signifie que le test correspondant ne protege rien.
#
# Mutations appliquees :
#   1. FACTURE_FOURNISSEUR retire de AffairLinkSupport.DIRECT_AFFAIR_TABLES
#   2. la colonne de liaison vers le parent n'est plus verifiee (planTab)
#   3. preferParent ignore (les lignes repassent en filtre direct)
#   4. une table retiree du script SQL de migration
#   5. l'affaire technique « Indefini » (ID 1) est acceptee comme une affaire
#   6. la migration ajoute une colonne sur une table de lignes
#   7. la contrainte SQL de migration est validee d'emblee (plus de NOT VALID)
#   8. le scenario de creation tourne sans la migration (base d'avant correctif)
#   9. base client ET migration sans colonne sur FACTURE_FOURNISSEUR
#
# Prerequis : un JDK (javac/java) et, pour les mutations 7 a 9, node + pglite.
#
# Usage : sh scripts/test-mutations-affaire.sh
#
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK_DIR=${WORK_DIR:-$(mktemp -d)}
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

# Prepare une copie propre du depot dans $WORK_DIR/copie.
prepare() {
    rm -rf "$WORK_DIR/copie"
    mkdir -p "$WORK_DIR/copie"
    for item in src tests scripts node_modules package.json; do
        if [ -e "$ROOT_DIR/$item" ]; then
            cp -R "$ROOT_DIR/$item" "$WORK_DIR/copie/"
        fi
    done
}

# Remplace $2 par $3 dans le fichier $1 de la copie (echoue si $2 est absent).
replace() {
    python3 - "$WORK_DIR/copie/$1" "$2" "$3" <<'PY'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, encoding='utf-8', newline='') as handle:
    content = handle.read()
if content.count(old) != 1:
    sys.stderr.write("motif introuvable ou ambigu dans %s\n" % path)
    sys.exit(2)
with open(path, 'w', encoding='utf-8', newline='') as handle:
    handle.write(content.replace(old, new, 1))
PY
}

# Verifie que la suite de tests Java echoue apres mutation.
expect_java_failure() {
    if (cd "$WORK_DIR/copie" && sh scripts/run-tests.sh > "$WORK_DIR/java.log" 2>&1); then
        ko "$1 (la suite Java passe alors qu'elle devrait echouer)"
        sed -n '1,12p' "$WORK_DIR/java.log" | sed 's/^/       /'
    else
        ok "$1"
    fi
}

# Verifie que la suite Java passe (mutation neutre, controle de sante).
expect_java_success() {
    if (cd "$WORK_DIR/copie" && sh scripts/run-tests.sh > "$WORK_DIR/java.log" 2>&1); then
        ok "$1"
    else
        ko "$1 (la suite Java echoue sur une copie non modifiee)"
        sed -n '1,20p' "$WORK_DIR/java.log" | sed 's/^/       /'
    fi
}

# Mutations 0 a 6 : elles compilent le module, donc il faut un JDK. Elles sont
# regroupees dans une fonction pour etre sautees proprement quand aucun JDK
# n'est installe sur la machine de test (le reste de la suite tourne alors
# quand meme : mutations SQL et scenario).
mutations_java() {
echo "== 0. controle : la copie non modifiee doit passer =="
prepare
expect_java_success "copie non modifiee : tests au vert"

echo "== 1. FACTURE_FOURNISSEUR hors de la liste du module =="
prepare
replace src/org/openconcerto/modules/project/AffairLinkSupport.java \
    '            "COMMANDE",
            "FACTURE_FOURNISSEUR",' \
    '            "COMMANDE",'
expect_java_failure "facture fournisseur oubliee : detecte"

echo "== 2. colonne de liaison vers le parent non verifiee =="
prepare
replace src/org/openconcerto/modules/project/AffairLinkSupport.java \
    'if (known != null && schema.hasField(known.getParentTable(), AFFAIR_FIELD) && schema.hasField(known.getChildTable(), known.getChildField())) {' \
    'if (known != null && schema.hasField(known.getParentTable(), AFFAIR_FIELD)) {'
expect_java_failure "lien parent sans colonne de liaison : detecte"

echo "== 3. preferParent ignore =="
prepare
replace src/org/openconcerto/modules/project/AffairLinkSupport.java \
    'if (preferParent && parentLink != null' \
    'if (false && parentLink != null'
expect_java_failure "lignes filtrees directement au lieu du document : detecte"

echo "== 4. table oubliee dans le script SQL de migration =="
prepare
replace tests/sql/migration-affaire-fournisseur.sql \
    '-- table: FACTURE_FOURNISSEUR
alter table "__SCHEMA__"."FACTURE_FOURNISSEUR" add column if not exists "ID_AFFAIRE" integer;' \
    '-- (mutation : table volontairement oubliee)'
expect_java_failure "derive entre le Java et le SQL de migration : detectee"

echo "== 5. affaire technique acceptee comme une vraie affaire =="
prepare
replace src/org/openconcerto/modules/project/AffairLinkSupport.java \
    'return affairID != null && affairID.intValue() > UNDEFINED_ID;' \
    'return affairID != null;'
expect_java_failure "affaire « Indefini » acceptee : detecte"

echo "== 6. migration qui ajoute une colonne sur une table de lignes =="
prepare
replace src/org/openconcerto/modules/project/AffairLinkSupport.java \
    '            "DEMANDE_ACHAT_ELEMENT"));' \
    '            "DEMANDE_ACHAT_ELEMENT",
            "COMMANDE_ELEMENT"));'
expect_java_failure "colonne d affaire ajoutee sur une table de lignes : detecte"
}

if command -v javac >/dev/null 2>&1 && command -v java >/dev/null 2>&1; then
    mutations_java
else
    echo "(javac/java absents : mutations Java 0 a 6 ignorees)"
fi

echo "== 7. contrainte SQL validee d'emblee (plus de NOT VALID) =="
if command -v node >/dev/null 2>&1; then
    prepare
    replace tests/sql/migration-affaire-fournisseur.sql \
        'references %I.%I (%I) not valid' \
        'references %I.%I (%I)'
    if (cd "$WORK_DIR/copie" && sh tests/sql/e2e-affaire-fournisseur.sh > "$WORK_DIR/e2e.log" 2>&1); then
        ko "migration bloquee par les affaires inexistantes : non detectee"
    else
        ok "migration bloquee par les affaires inexistantes : detectee"
    fi
else
    echo "(node absent : mutation 7 ignoree)"
fi

echo "== 8. scenario de creation sans la migration (symptome d'origine) =="
if command -v node >/dev/null 2>&1; then
    prepare
    if (cd "$WORK_DIR/copie" && SANS_MIGRATION=1 sh tests/sql/scenario-creation-fournisseur.sh > "$WORK_DIR/scenario.log" 2>&1); then
        ko "commande fournisseur sans colonne d'affaire : symptome non detecte"
        sed -n '1,10p' "$WORK_DIR/scenario.log" | sed 's/^/       /'
    else
        ok "commande fournisseur sans colonne d'affaire : detecte"
    fi
else
    echo "(node absent : mutation 8 ignoree)"
fi

echo "== 9. base client ET migration sans colonne sur FACTURE_FOURNISSEUR =="
# Reproduction exacte du defaut D1 de l'audit : la facture fournisseur n'a pas
# de colonne d'affaire (ni dans la base du client, ni dans la migration). Une
# facture fournisseur rattachee a une affaire doit alors etre IMPOSSIBLE : le
# scenario doit echouer, sinon il ne prouve rien sur ce chemin.
if command -v node >/dev/null 2>&1; then
    prepare
    replace tests/sql/fixture-affaire-fournisseur.sql \
        '    "INFOS" varchar(1024),
    "ID_AFFAIRE" integer
);' \
        '    "INFOS" varchar(1024)
);'
    replace tests/sql/migration-affaire-fournisseur.sql \
        '-- table: FACTURE_FOURNISSEUR
alter table "__SCHEMA__"."FACTURE_FOURNISSEUR" add column if not exists "ID_AFFAIRE" integer;' \
        '-- (mutation : facture fournisseur volontairement oubliee)'
    if (cd "$WORK_DIR/copie" && sh tests/sql/scenario-creation-fournisseur.sh > "$WORK_DIR/scenario.log" 2>&1); then
        ko "facture fournisseur sans colonne d'affaire : non detecte par le scenario"
        sed -n '1,10p' "$WORK_DIR/scenario.log" | sed 's/^/       /'
    else
        ok "facture fournisseur sans colonne d'affaire : detecte par le scenario"
    fi
else
    echo "(node absent : mutation 9 ignoree)"
fi

echo
echo "Controles : $CONTROLES | echecs : $ECHECS"
if [ "$ECHECS" -ne 0 ]; then
    echo "RESULTAT : ECHEC"
    exit 1
fi
echo "RESULTAT : OK"
