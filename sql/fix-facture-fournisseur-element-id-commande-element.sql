-- Correctif PostgreSQL pour l'erreur OpenConcerto :
--   "ID_COMMANDE_ELEMENT is not in table /FACTURE_FOURNISSEUR_ELEMENT/"
--   (transfert des commandes fournisseur -> factures fournisseur)
--
-- Cause : la table FACTURE_FOURNISSEUR_ELEMENT n'a pas la colonne ID_COMMANDE_ELEMENT
-- (lien ligne de facture fournisseur -> ligne de commande fournisseur),
-- alors que le code de transfert tente de la renseigner.
--
-- Le script est idempotent : il peut être relancé sans erreur.
-- Adapter le nom du schéma ci-dessous à celui de votre base (ex. "OpenConcerto42").
-- Sauvegarder la base avant d'exécuter le script.

BEGIN;

SET LOCAL search_path TO "OpenConcerto42";

-- 1. Colonne (même définition que celle générée par OpenConcerto pour une clé étrangère :
--    int, valeur par défaut 1 = ligne "indéfinie" de COMMANDE_ELEMENT)
ALTER TABLE "FACTURE_FOURNISSEUR_ELEMENT"
    ADD COLUMN IF NOT EXISTS "ID_COMMANDE_ELEMENT" int DEFAULT 1;

-- 2. Clé étrangère vers COMMANDE_ELEMENT(ID), ajoutée seulement si elle n'existe pas
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = current_schema()
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

-- Vérification (doit renvoyer une ligne avec data_type = 'integer') :
-- SELECT column_name, data_type, column_default
-- FROM information_schema.columns
-- WHERE table_schema = 'OpenConcerto42'
--   AND table_name = 'FACTURE_FOURNISSEUR_ELEMENT'
--   AND column_name = 'ID_COMMANDE_ELEMENT';
