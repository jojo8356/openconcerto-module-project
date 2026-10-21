#!/usr/bin/env bash
#
# Test de bout en bout de scripts/test-droits-utilisateur.sh.
#
# Le script est exécuté tel quel, avec un « psql » qui est un vrai moteur
# PostgreSQL (pglite, PostgreSQL compilé en WebAssembly). Les tables sont
# créées comme OpenConcerto les crée : noms de tables et de colonnes en
# MAJUSCULES, entre guillemets. C'est ce qui permet de détecter les
# requêtes qui oublient les guillemets — PostgreSQL replie alors les
# identifiants en minuscules et la requête échoue.
#
# Prérequis : npm install @electric-sql/pglite
# Exécution : bash tests/sql/e2e-droits.sh
#
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
export PGLITE_DIR="${PGLITE_DIR:-$(mktemp -d)}"
export PATH="$HERE/bin:$PATH"

PASS=0
FAIL=0
check() {
    local label="$1" expected="$2" got="$3"
    if [ "$expected" = "$got" ]; then
        echo "OK   $label : $got"
        PASS=$((PASS + 1))
    else
        echo "FAIL $label : obtenu '$got', attendu '$expected'"
        FAIL=$((FAIL + 1))
    fi
}
contains() {
    local label="$1" needle="$2" hay="$3"
    if printf '%s' "$hay" | grep -qF -- "$needle"; then
        echo "OK   $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL $label : '$needle' absent"
        FAIL=$((FAIL + 1))
    fi
}
not_contains() {
    local label="$1" needle="$2" hay="$3"
    if printf '%s' "$hay" | grep -qF -- "$needle"; then
        echo "FAIL $label : '$needle' présent"
        FAIL=$((FAIL + 1))
    else
        echo "OK   $label"
        PASS=$((PASS + 1))
    fi
}

echo "== préparation de la base de test (pglite : $PGLITE_DIR) =="
psql -X -d postgres -v ON_ERROR_STOP=1 -f - <<'SQL'
create schema "Common";
create table "Common"."USER_COMMON" (
  "ID" serial primary key, "LOGIN" text, "NOM" text, "PRENOM" text,
  "PASSWORD" text, "ADMIN" boolean default false, "SUPERUSER" boolean default false);
create table "Common"."RIGHT" (
  "ID" serial primary key, "CODE" varchar(128), "NOM" varchar(256), "DESCRIPTION" varchar(500));
create table "Common"."USER_RIGHT" (
  "ID" serial primary key, "ID_USER_COMMON" int, "ID_RIGHT" int,
  "OBJECT" varchar(150) null, "HAVE_RIGHT" boolean not null);
create table "Common"."ACCES_SOCIETE" (
  "ID" serial primary key, "ID_USER_COMMON" int, "ID_SOCIETE_COMMON" int);

insert into "Common"."USER_COMMON" ("ID","LOGIN","NOM","PRENOM","ADMIN","SUPERUSER") values
  (1,'admin','Administrateur','',true,true),
  (2,'yves','POLSINELLI','Yves',false,false),
  (3,'gisele','ABE','Gisèle',false,false);

insert into "Common"."RIGHT" ("ID","CODE","NOM") values
  (1,'TABLE_ALL_RIGHTS','Tous les droits'),
  (2,'TABLE_ALL_MODIF_RIGHTS','Droits de modification'),
  (3,'INSERT_ROW','Insertion'),
  (4,'UPDATE_ROW','Modification'),
  (5,'SELECT_ROW','Consultation'),
  (6,'DROIT_SPECIFIQUE','Droit maison');

-- Yves : tous les droits
insert into "Common"."USER_RIGHT" ("ID","ID_USER_COMMON","ID_RIGHT","OBJECT","HAVE_RIGHT") values
  (10, 2, 1, null, true);
-- Gisele : refus en ID 20 puis autorisation en ID 21 -> la 20 l'emporte
insert into "Common"."USER_RIGHT" ("ID","ID_USER_COMMON","ID_RIGHT","OBJECT","HAVE_RIGHT") values
  (20, 3, 1, null, false),
  (21, 3, 1, null, true);

insert into "Common"."ACCES_SOCIETE" ("ID_USER_COMMON","ID_SOCIETE_COMMON") values (2,42),(3,42);
SQL

echo
echo "== 1. rapport =="
set +e
OUT=$(bash "$REPO/scripts/test-droits-utilisateur.sh" -1 yves -2 gisele 2>&1)
RC=$?
set -e
echo "$OUT" | sed 's/^/    /'
echo
check "code de sortie" "0" "$RC"
contains "table des droits détectée" "droits       : Common.USER_RIGHT" "$OUT"
contains "droits manquants détectés" "droits accordés à yves mais absents ou refusés pour gisele : 1" "$OUT"
contains "lignes masquées détectées" "lignes de gisele ignorées par OpenConcerto (masquées)     : 1" "$OUT"
contains "verdict" "ligne(s) de USER_RIGHT pour gisele sont IGNORÉES par OpenConcerto" "$OUT"
not_contains "aucune erreur SQL" "n'existe pas" "$OUT"

echo
echo "== 2. correctif (dry-run) =="
set +e
OUTFIX=$(bash "$REPO/scripts/test-droits-utilisateur.sh" -1 yves -2 gisele -f -n 2>&1)
RCFIX=$?
set -e
echo "$OUTFIX" | sed 's/^/    /'
echo
check "code de sortie (dry-run)" "0" "$RCFIX"
contains "UPDATE généré" 'UPDATE "Common"."USER_RIGHT" SET "HAVE_RIGHT" = true WHERE "ID" = 20;' "$OUTFIX"
contains "ligne masquée supprimée" 'DELETE FROM "Common"."USER_RIGHT" WHERE "ID" = 21;' "$OUTFIX"
not_contains "pas d'INSERT (la ligne effective existe déjà)" 'INSERT INTO "Common"."USER_RIGHT"' "$OUTFIX"
contains "rien n'a été appliqué" "Dry-run : rien n'a été appliqué" "$OUTFIX"

echo
echo "== 3. application du correctif =="
set +e
OUTAPP=$(bash "$REPO/scripts/test-droits-utilisateur.sh" -1 yves -2 gisele -f -y 2>&1)
RCAPP=$?
set -e
echo "$OUTAPP" | sed 's/^/    /'
echo
check "code de sortie (application)" "0" "$RCAPP"
contains "correctif appliqué" "Correctif appliqué" "$OUTAPP"
contains "reconnexion conseillée" "doit se reconnecter" "$OUTAPP"
ROLLBACK=$(printf '%s' "$OUTAPP" | sed -n 's/^  Script de restauration : //p' | head -1)
echo "    script de restauration : $ROLLBACK"

echo
echo "== 4. état après correctif =="
STATE=$(psql -X -A -t -d postgres -c 'select "ID", "HAVE_RIGHT" from "Common"."USER_RIGHT" where "ID_USER_COMMON"=3 order by "ID"' | paste -sd'|' -)
echo "    lignes de gisele : $STATE"
check "une seule ligne pour gisele" "20|t" "$STATE"

REPORT2=$(bash "$REPO/scripts/test-droits-utilisateur.sh" -1 yves -2 gisele 2>&1)
contains "plus aucun droit manquant" "droits accordés à yves mais absents ou refusés pour gisele : 0" "$REPORT2"

echo
echo "== 5. restauration (rollback) =="
if [ -n "$ROLLBACK" ] && [ -f "$ROLLBACK" ]; then
    psql -X -d postgres -v ON_ERROR_STOP=1 -f "$ROLLBACK" >/dev/null
    STATE=$(psql -X -A -t -d postgres -c 'select "ID", "HAVE_RIGHT" from "Common"."USER_RIGHT" where "ID_USER_COMMON"=3 order by "ID"' | paste -sd'|' -)
    NB=$(psql -X -A -t -d postgres -c 'select count(*) from "Common"."USER_RIGHT" where "ID_USER_COMMON"=3')
    PREMIER=$(psql -X -A -t -d postgres -c 'select "HAVE_RIGHT" from "Common"."USER_RIGHT" where "ID_USER_COMMON"=3 order by "ID" limit 1')
    echo "    lignes de gisele après rollback : $STATE"
    # Les identifiants sont réattribués par la séquence (pour ne pas la
    # désynchroniser) : c'est l'ordre et le contenu qui comptent.
    check "2 lignes restaurées" "2" "$NB"
    check "droit effectif restauré à faux (la plus ancienne ligne l'emporte)" "f" "$PREMIER"
    REPORT3=$(bash "$REPO/scripts/test-droits-utilisateur.sh" -1 yves -2 gisele 2>&1)
    contains "écart de nouveau détecté" "droits accordés à yves mais absents ou refusés pour gisele : 1" "$REPORT3"
else
    echo "FAIL script de restauration introuvable"
    FAIL=$((FAIL + 1))
fi

echo
echo "== 6. droits partiels par table (cas Paul) =="
# Les codes de droits 3 (INSERT_ROW) et 5 (SELECT_ROW) existent deja.
psql -X -d postgres -v ON_ERROR_STOP=1 -f - <<'SQL'
insert into "Common"."USER_COMMON" ("ID","LOGIN","NOM","PRENOM") values (4,'paul','DUPONT','Paul');
insert into "Common"."USER_RIGHT" ("ID","ID_USER_COMMON","ID_RIGHT","OBJECT","HAVE_RIGHT") values
  (30, 4, 3, '"OpenConcerto42"."FACTURE_FOURNISSEUR"', true),
  (31, 4, 5, '"OpenConcerto42"."FACTURE_FOURNISSEUR"', true);
SQL
OUTP=$(bash "$REPO/scripts/test-droits-utilisateur.sh" -1 yves -2 paul 2>&1)
echo "$OUTP" | sed -n '/Droits sur les tables du transfert/,/Accès aux sociétés/p' | sed 's/^/    /'
contains "droit par table détecté" "INSERT_ROW" "$OUTP"
contains "objet tableau détecté" "FACTURE_FOURNISSEUR" "$OUTP"

echo
echo "== 7. retour à la base native (retrait des identifiants) =="
set +e
OUTN=$(bash "$REPO/scripts/test-droits-utilisateur.sh" -1 yves -2 gisele -b OpenConcertoKineticTherm -p 5432 -H localhost 2>&1)
RCN=$?
set -e
check "code de sortie (cible native)" "0" "$RCN"

echo
if [ "$FAIL" -eq 0 ]; then
  echo "TOUS LES CONTROLES PASSENT ($PASS)"
  exit 0
else
  echo "$FAIL CONTROLE(S) EN ECHEC (sur $PASS)"
  exit 1
fi
