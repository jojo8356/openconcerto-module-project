-- =====================================================================
-- Correctif OpenConcerto 1.7.6 (PostgreSQL)
--
-- Erreur :
--   "ID_COMMANDE_ELEMENT is not in table /FACTURE_FOURNISSEUR_ELEMENT/"
--   (transfert des commandes fournisseur -> factures fournisseur)
--
-- Cause : la table "OpenConcerto42"."FACTURE_FOURNISSEUR_ELEMENT" n'a pas la
-- colonne ID_COMMANDE_ELEMENT (lien ligne de facture -> ligne de commande).
--
-- Schéma : "OpenConcerto42" (vérifié dans le dump OC-v1.7.6-Noon_Dump_2026-10-09).
-- Script idempotent : il peut être relancé sans erreur.
-- Usage : psql -d OpenConcerto -f fix-facture-fournisseur-element-id-commande-element.sql
-- =====================================================================

BEGIN;

SET LOCAL search_path TO "OpenConcerto42";

-- 0. Vérifications préalables : les deux tables doivent exister
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                   WHERE table_schema = 'OpenConcerto42' AND table_name = 'FACTURE_FOURNISSEUR_ELEMENT') THEN
        RAISE EXCEPTION 'Table OpenConcerto42.FACTURE_FOURNISSEUR_ELEMENT introuvable (mauvais schéma ou mauvaise base ?)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                   WHERE table_schema = 'OpenConcerto42' AND table_name = 'COMMANDE_ELEMENT') THEN
        RAISE EXCEPTION 'Table OpenConcerto42.COMMANDE_ELEMENT introuvable';
    END IF;
END $$;

-- 1. Colonne : int avec valeur par défaut 1 (ligne "indéfinie"), comme les autres clés étrangères
ALTER TABLE "FACTURE_FOURNISSEUR_ELEMENT"
    ADD COLUMN IF NOT EXISTS "ID_COMMANDE_ELEMENT" int DEFAULT 1;

-- 2. Clé étrangère vers COMMANDE_ELEMENT("ID"), ajoutée seulement si absente
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = 'OpenConcerto42'
          AND t.relname = 'FACTURE_FOURNISSEUR_ELEMENT'
          AND c.conname = 'FACTURE_FOURNISSEUR_ELEMENT_ID_COMMANDE_ELEMENT_fkey'
    ) THEN
        ALTER TABLE "FACTURE_FOURNISSEUR_ELEMENT"
            ADD CONSTRAINT "FACTURE_FOURNISSEUR_ELEMENT_ID_COMMANDE_ELEMENT_fkey"
            FOREIGN KEY ("ID_COMMANDE_ELEMENT") REFERENCES "COMMANDE_ELEMENT" ("ID");
    END IF;
END $$;

-- 3. Index sur la clé étrangère (convention OpenConcerto : suffixe _fki)
CREATE INDEX IF NOT EXISTS "FACTURE_FOURNISSEUR_ELEMENT_ID_COMMANDE_ELEMENT_fki"
    ON "FACTURE_FOURNISSEUR_ELEMENT" ("ID_COMMANDE_ELEMENT");

COMMIT;

-- 4. Vérification (doit afficher : ID_COMMANDE_ELEMENT | integer | 1)
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_schema = 'OpenConcerto42'
  AND table_name = 'FACTURE_FOURNISSEUR_ELEMENT'
  AND column_name = 'ID_COMMANDE_ELEMENT';
