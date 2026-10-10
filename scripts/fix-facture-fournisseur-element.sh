#!/usr/bin/env bash
#
# Correctif OpenConcerto 1.7.6 : ajoute FACTURE_FOURNISSEUR_ELEMENT.ID_COMMANDE_ELEMENT
#
# 1. Vérifie les outils et la connexion à la base
# 2. Sauvegarde la base (avant modification)
# 3. Applique le correctif SQL (idempotent)
# 4. Vérifie la colonne
# 5. Crée un dump complet à jour, à donner à une autre installation
#
# Usage :
#   ./fix-facture-fournisseur-element.sh [-d base] [-s schema] [-U user] [-h hote] [-p port] [-o dossier] [-y]
#
# Exemple :
#   ./fix-facture-fournisseur-element.sh -d OpenConcerto -U postgres -y
#
# Les connexions utilisent les variables PG* standard si elles sont définies
# (PGHOST, PGPORT, PGUSER, PGPASSWORD ou ~/.pgpass).

set -euo pipefail

DB="${PGDATABASE:-OpenConcerto}"
SCHEMA="OpenConcerto42"
OUTDIR="oc-update-$(date +%Y-%m-%d)"
ASSUME_YES=0

usage() {
    sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while getopts ":d:s:U:h:p:o:y" opt; do
    case "$opt" in
        d) DB="$OPTARG" ;;
        s) SCHEMA="$OPTARG" ;;
        U) export PGUSER="$OPTARG" ;;
        h) export PGHOST="$OPTARG" ;;
        p) export PGPORT="$OPTARG" ;;
        o) OUTDIR="$OPTARG" ;;
        y) ASSUME_YES=1 ;;
        *) usage 1 ;;
    esac
done

log() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERREUR : %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- 1. Vérifications
log "Vérification des outils"
for cmd in psql pg_dump; do
    command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' introuvable. Installe le client PostgreSQL (version 15 ou plus)."
done
pg_dump --version

log "Connexion à la base '$DB'"
psql -d "$DB" -v ON_ERROR_STOP=1 -tAc "SELECT 1" >/dev/null \
    || die "Impossible de se connecter à la base '$DB' (vérifie -d, -U, -h, -p et le mot de passe)."

TABLE_OK=$(psql -d "$DB" -tAc "SELECT count(*) FROM information_schema.tables WHERE table_schema='$SCHEMA' AND table_name='FACTURE_FOURNISSEUR_ELEMENT'")
CMD_OK=$(psql -d "$DB" -tAc "SELECT count(*) FROM information_schema.tables WHERE table_schema='$SCHEMA' AND table_name='COMMANDE_ELEMENT'")
[ "$TABLE_OK" = "1" ] || die "Table $SCHEMA.FACTURE_FOURNISSEUR_ELEMENT introuvable. Vérifie -d et -s."
[ "$CMD_OK" = "1" ] || die "Table $SCHEMA.COMMANDE_ELEMENT introuvable. Vérifie -d et -s."

mkdir -p "$OUTDIR"
DATE_TAG=$(date +%Y-%m-%d_%H%M)
BACKUP="$OUTDIR/backup_avant_fix_${DATE_TAG}.dumpsql"
FIXSQL="$OUTDIR/fix_${DATE_TAG}.sql"
FINAL_DUMP="$OUTDIR/OpenConcerto-1.7.6-a-jour_${DATE_TAG}.dumpsql"

if [ "$ASSUME_YES" -ne 1 ]; then
    printf '\nLe script va sauvegarder la base "%s", appliquer le correctif sur le schéma "%s" et créer un dump dans "%s".\nContinuer ? [o/N] ' "$DB" "$SCHEMA" "$OUTDIR"
    read -r answer
    case "$answer" in
        o|O|oui|OUI|y|Y) ;;
        *) echo "Annulé."; exit 0 ;;
    esac
fi

# ---------------------------------------------------------------- 2. Sauvegarde
log "Sauvegarde avant correctif : $BACKUP"
pg_dump -Fc -d "$DB" -f "$BACKUP" || die "Échec de la sauvegarde. Aucune modification n'a été faite."

# ---------------------------------------------------------------- 3. Correctif
log "Écriture et application du correctif"
cat > "$FIXSQL" <<'EOSQL'
BEGIN;

SET LOCAL search_path TO "__SCHEMA__";

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                   WHERE table_schema = '__SCHEMA__' AND table_name = 'FACTURE_FOURNISSEUR_ELEMENT') THEN
        RAISE EXCEPTION 'Table __SCHEMA__.FACTURE_FOURNISSEUR_ELEMENT introuvable';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                   WHERE table_schema = '__SCHEMA__' AND table_name = 'COMMANDE_ELEMENT') THEN
        RAISE EXCEPTION 'Table __SCHEMA__.COMMANDE_ELEMENT introuvable';
    END IF;
END $$;

ALTER TABLE "FACTURE_FOURNISSEUR_ELEMENT"
    ADD COLUMN IF NOT EXISTS "ID_COMMANDE_ELEMENT" int DEFAULT 1;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = '__SCHEMA__'
          AND t.relname = 'FACTURE_FOURNISSEUR_ELEMENT'
          AND c.conname = 'FACTURE_FOURNISSEUR_ELEMENT_ID_COMMANDE_ELEMENT_fkey'
    ) THEN
        ALTER TABLE "FACTURE_FOURNISSEUR_ELEMENT"
            ADD CONSTRAINT "FACTURE_FOURNISSEUR_ELEMENT_ID_COMMANDE_ELEMENT_fkey"
            FOREIGN KEY ("ID_COMMANDE_ELEMENT") REFERENCES "COMMANDE_ELEMENT" ("ID");
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS "FACTURE_FOURNISSEUR_ELEMENT_ID_COMMANDE_ELEMENT_fki"
    ON "FACTURE_FOURNISSEUR_ELEMENT" ("ID_COMMANDE_ELEMENT");

COMMIT;
EOSQL
# Remplace le placeholder par le nom de schéma réel (échappement des guillemets doubles)
sed -i "s/__SCHEMA__/${SCHEMA}/g" "$FIXSQL"

psql -d "$DB" -v ON_ERROR_STOP=1 -q -f "$FIXSQL" || die "Le correctif a échoué. La transaction a été annulée ; la sauvegarde est dans $BACKUP."

# ---------------------------------------------------------------- 4. Vérification
log "Vérification de la colonne"
RESULT=$(psql -d "$DB" -tAc "SELECT data_type || '|' || column_default FROM information_schema.columns WHERE table_schema='$SCHEMA' AND table_name='FACTURE_FOURNISSEUR_ELEMENT' AND column_name='ID_COMMANDE_ELEMENT'")
echo "ID_COMMANDE_ELEMENT : $RESULT"
case "$RESULT" in
    integer\|1) echo "OK : la colonne est en place." ;;
    *) die "Vérification échouée (résultat attendu : integer|1)." ;;
esac

# ---------------------------------------------------------------- 5. Dump à jour
log "Création du dump complet à jour : $FINAL_DUMP"
pg_dump -Fc --no-owner --no-privileges -d "$DB" -f "$FINAL_DUMP"
if command -v sha256sum >/dev/null 2>&1; then
    (cd "$OUTDIR" && sha256sum "$(basename "$FINAL_DUMP")" > "$(basename "$FINAL_DUMP").sha256")
    echo "Empreinte : $FINAL_DUMP.sha256"
fi

cat <<EOF

Terminé.

- Sauvegarde avant correctif : $BACKUP
- Dump à jour à transmettre  : $FINAL_DUMP

Ce dump contient toutes les données de la société : transmets-le par un canal sûr.
Pour la restauration chez l'autre installation, utilise restore-openconcerto-dump.sh
(PostgreSQL 15 ou plus, OpenConcerto 1.7.6 et le module installés).
EOF
