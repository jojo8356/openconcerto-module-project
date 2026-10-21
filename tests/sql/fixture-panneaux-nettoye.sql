--
-- Variante « sans anomalie » de la base de test des panneaux.
--
-- A appliquer apres tests/sql/fixture-panneaux.sql : on supprime les
-- anomalies plantees volontairement et on retablit la colonne
-- ID_COMMANDE_ELEMENT, pour verifier que la suite de tests passe (code de
-- sortie 0) sur une base saine.
--
BEGIN;

SET LOCAL search_path TO "OpenConcerto42";

-- Lignes orphelines ou sans affaire : elles disparaissent des panneaux.
DELETE FROM "DEVIS" WHERE "ID_DEVIS" = 3;
DELETE FROM "DEVIS" WHERE "ID_DEVIS" = 4;
DELETE FROM "SAISIE_VENTE_FACTURE" WHERE "ID" = 3;
DELETE FROM "COMMANDE_ELEMENT" WHERE "ID" = 2;
DELETE FROM "COMMANDE" WHERE "ID" = 2;

-- Le devis 5 passe « en attente » : l'onglet « Devis en attente » affiche
-- donc une ligne.
UPDATE "DEVIS" SET "ID_ETAT_DEVIS" = 2 WHERE "ID_DEVIS" = 5;

-- Colonne de rattachement de la ligne de facture fournisseur a la ligne de
-- commande (le correctif applique en production).
ALTER TABLE "FACTURE_FOURNISSEUR_ELEMENT" ADD COLUMN IF NOT EXISTS "ID_COMMANDE_ELEMENT" integer DEFAULT 1;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'FACTURE_FOURNISSEUR_ELEMENT_ID_COMMANDE_ELEMENT_fkey') THEN
    ALTER TABLE "FACTURE_FOURNISSEUR_ELEMENT" ADD CONSTRAINT "FACTURE_FOURNISSEUR_ELEMENT_ID_COMMANDE_ELEMENT_fkey"
      FOREIGN KEY ("ID_COMMANDE_ELEMENT") REFERENCES "COMMANDE_ELEMENT" ("ID");
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS "FACTURE_FOURNISSEUR_ELEMENT_ID_COMMANDE_ELEMENT_fki" ON "FACTURE_FOURNISSEUR_ELEMENT" ("ID_COMMANDE_ELEMENT");

-- Le refus de lecture de Gisele sur les devis est leve.
UPDATE "Common"."USER_RIGHT" SET "HAVE_RIGHT" = true WHERE "ID_USER_COMMON" = 18 AND "OBJECT" = 'DEVIS';

COMMIT;
