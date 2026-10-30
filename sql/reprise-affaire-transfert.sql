-- Reprise des affaires perdues lors des transferts de documents.
--
-- A executer quand le module n'est pas disponible, ou pour verifier a la main ce
-- que fait le menu « Aide > Reprendre les affaires des documents ». Les regles
-- sont identiques (AffairBackfillSupport) : on ne remplit QUE le vide, jamais
-- une affaire deja renseignee, et seulement quand la source porte une vraie
-- affaire (ID > 1, l'affaire « Indefini » n'en est pas une).
--
-- Ce fichier ne touche que les EN-TETES de documents : les 17 transferts et les deux
-- saisies d'achat. Les tableaux de lignes sont dans
-- `sql/reprise-affaire-lignes.sql`, parce que la colonne n'existe pas sur tous.
--
-- Chaque bloc est dans SA PROPRE transaction : sur une base ou une table n'a pas
-- la colonne attendue (constate : DEVIS n'a pas de colonne ID), le bloc
-- concerne signale l'erreur et les autres sont quand meme appliques.
--
--   sh scripts/oc-psql.sh -f sql/reprise-affaire-transfert.sql
--
-- En cas de doute, remplacer un COMMIT par ROLLBACK.
--
-- Idempotent : rejouable autant de fois que voulu.
--
-- Verifie automatiquement, sans base :  sh scripts/test-affaire-cli.sh


\echo '=== 1. Saisies d achat : SOURCE / IDSOURCE ==='

-- Commande -> saisie d'achat

BEGIN;

UPDATE "OpenConcerto42"."SAISIE_ACHAT"
   SET "ID_AFFAIRE" = "OpenConcerto42"."COMMANDE"."ID_AFFAIRE"
  FROM "OpenConcerto42"."COMMANDE"
 WHERE "OpenConcerto42"."SAISIE_ACHAT"."SOURCE" = 'COMMANDE'
   AND "OpenConcerto42"."SAISIE_ACHAT"."IDSOURCE" = "OpenConcerto42"."COMMANDE"."ID"
   AND ("OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" > 1;

COMMIT;

-- Bon_reception -> saisie d'achat

BEGIN;

UPDATE "OpenConcerto42"."SAISIE_ACHAT"
   SET "ID_AFFAIRE" = "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE"
  FROM "OpenConcerto42"."BON_RECEPTION"
 WHERE "OpenConcerto42"."SAISIE_ACHAT"."SOURCE" = 'BON_RECEPTION'
   AND "OpenConcerto42"."SAISIE_ACHAT"."IDSOURCE" = "OpenConcerto42"."BON_RECEPTION"."ID"
   AND ("OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" > 1;

COMMIT;

\echo '=== 2. Documents : via les tables de transfert du coeur ==='

\echo 'Chaque bloc est independant : une table absente n empeche pas les autres.'
\echo ''

-- COMMANDE -> SAISIE_ACHAT

BEGIN;

UPDATE "OpenConcerto42"."SAISIE_ACHAT"
   SET "ID_AFFAIRE" = "OpenConcerto42"."COMMANDE"."ID_AFFAIRE"
  FROM "OpenConcerto42"."TR_COMMANDE"
  JOIN "OpenConcerto42"."COMMANDE" ON "OpenConcerto42"."COMMANDE"."ID" = "OpenConcerto42"."TR_COMMANDE"."ID_COMMANDE"
 WHERE "OpenConcerto42"."TR_COMMANDE"."ID_SAISIE_ACHAT" = "OpenConcerto42"."SAISIE_ACHAT"."ID" AND "OpenConcerto42"."TR_COMMANDE"."ID_COMMANDE" = "OpenConcerto42"."COMMANDE"."ID"
   AND ("OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" > 1;

COMMIT;

-- COMMANDE -> BON_RECEPTION

BEGIN;

UPDATE "OpenConcerto42"."BON_RECEPTION"
   SET "ID_AFFAIRE" = "OpenConcerto42"."COMMANDE"."ID_AFFAIRE"
  FROM "OpenConcerto42"."TR_COMMANDE"
  JOIN "OpenConcerto42"."COMMANDE" ON "OpenConcerto42"."COMMANDE"."ID" = "OpenConcerto42"."TR_COMMANDE"."ID_COMMANDE"
 WHERE "OpenConcerto42"."TR_COMMANDE"."ID_BON_RECEPTION" = "OpenConcerto42"."BON_RECEPTION"."ID" AND "OpenConcerto42"."TR_COMMANDE"."ID_COMMANDE" = "OpenConcerto42"."COMMANDE"."ID"
   AND ("OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" > 1;

COMMIT;

-- COMMANDE -> FACTURE_FOURNISSEUR

BEGIN;

UPDATE "OpenConcerto42"."FACTURE_FOURNISSEUR"
   SET "ID_AFFAIRE" = "OpenConcerto42"."COMMANDE"."ID_AFFAIRE"
  FROM "OpenConcerto42"."TR_COMMANDE"
  JOIN "OpenConcerto42"."COMMANDE" ON "OpenConcerto42"."COMMANDE"."ID" = "OpenConcerto42"."TR_COMMANDE"."ID_COMMANDE"
 WHERE "OpenConcerto42"."TR_COMMANDE"."ID_FACTURE_FOURNISSEUR" = "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID" AND "OpenConcerto42"."TR_COMMANDE"."ID_COMMANDE" = "OpenConcerto42"."COMMANDE"."ID"
   AND ("OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" > 1;

COMMIT;

-- BON_RECEPTION -> SAISIE_ACHAT

BEGIN;

UPDATE "OpenConcerto42"."SAISIE_ACHAT"
   SET "ID_AFFAIRE" = "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE"
  FROM "OpenConcerto42"."TR_BON_RECEPTION"
  JOIN "OpenConcerto42"."BON_RECEPTION" ON "OpenConcerto42"."BON_RECEPTION"."ID" = "OpenConcerto42"."TR_BON_RECEPTION"."ID_BON_RECEPTION"
 WHERE "OpenConcerto42"."TR_BON_RECEPTION"."ID_SAISIE_ACHAT" = "OpenConcerto42"."SAISIE_ACHAT"."ID" AND "OpenConcerto42"."TR_BON_RECEPTION"."ID_BON_RECEPTION" = "OpenConcerto42"."BON_RECEPTION"."ID"
   AND ("OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" > 1;

COMMIT;

-- BON_RECEPTION -> FACTURE_FOURNISSEUR

BEGIN;

UPDATE "OpenConcerto42"."FACTURE_FOURNISSEUR"
   SET "ID_AFFAIRE" = "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE"
  FROM "OpenConcerto42"."TR_BON_RECEPTION"
  JOIN "OpenConcerto42"."BON_RECEPTION" ON "OpenConcerto42"."BON_RECEPTION"."ID" = "OpenConcerto42"."TR_BON_RECEPTION"."ID_BON_RECEPTION"
 WHERE "OpenConcerto42"."TR_BON_RECEPTION"."ID_FACTURE_FOURNISSEUR" = "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID" AND "OpenConcerto42"."TR_BON_RECEPTION"."ID_BON_RECEPTION" = "OpenConcerto42"."BON_RECEPTION"."ID"
   AND ("OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" > 1;

COMMIT;

-- DEVIS -> COMMANDE

BEGIN;

UPDATE "OpenConcerto42"."COMMANDE"
   SET "ID_AFFAIRE" = "OpenConcerto42"."DEVIS"."ID_AFFAIRE"
  FROM "OpenConcerto42"."TR_DEVIS"
  JOIN "OpenConcerto42"."DEVIS" ON "OpenConcerto42"."DEVIS"."ID" = "OpenConcerto42"."TR_DEVIS"."ID_DEVIS"
 WHERE "OpenConcerto42"."TR_DEVIS"."ID_COMMANDE" = "OpenConcerto42"."COMMANDE"."ID" AND "OpenConcerto42"."TR_DEVIS"."ID_DEVIS" = "OpenConcerto42"."DEVIS"."ID"
   AND ("OpenConcerto42"."COMMANDE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."DEVIS"."ID_AFFAIRE" > 1;

COMMIT;

-- SAISIE_ACHAT -> AVOIR_FOURNISSEUR

BEGIN;

UPDATE "OpenConcerto42"."AVOIR_FOURNISSEUR"
   SET "ID_AFFAIRE" = "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE"
  FROM "OpenConcerto42"."TR_SAISIE_ACHAT"
  JOIN "OpenConcerto42"."SAISIE_ACHAT" ON "OpenConcerto42"."SAISIE_ACHAT"."ID" = "OpenConcerto42"."TR_SAISIE_ACHAT"."ID_SAISIE_ACHAT"
 WHERE "OpenConcerto42"."TR_SAISIE_ACHAT"."ID_AVOIR_FOURNISSEUR" = "OpenConcerto42"."AVOIR_FOURNISSEUR"."ID" AND "OpenConcerto42"."TR_SAISIE_ACHAT"."ID_SAISIE_ACHAT" = "OpenConcerto42"."SAISIE_ACHAT"."ID"
   AND ("OpenConcerto42"."AVOIR_FOURNISSEUR"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."AVOIR_FOURNISSEUR"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" > 1;

COMMIT;

-- DEVIS -> COMMANDE_CLIENT

BEGIN;

UPDATE "OpenConcerto42"."COMMANDE_CLIENT"
   SET "ID_AFFAIRE" = "OpenConcerto42"."DEVIS"."ID_AFFAIRE"
  FROM "OpenConcerto42"."TR_DEVIS"
  JOIN "OpenConcerto42"."DEVIS" ON "OpenConcerto42"."DEVIS"."ID" = "OpenConcerto42"."TR_DEVIS"."ID_DEVIS"
 WHERE "OpenConcerto42"."TR_DEVIS"."ID_COMMANDE_CLIENT" = "OpenConcerto42"."COMMANDE_CLIENT"."ID" AND "OpenConcerto42"."TR_DEVIS"."ID_DEVIS" = "OpenConcerto42"."DEVIS"."ID"
   AND ("OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."DEVIS"."ID_AFFAIRE" > 1;

COMMIT;

-- DEVIS -> SAISIE_VENTE_FACTURE

BEGIN;

UPDATE "OpenConcerto42"."SAISIE_VENTE_FACTURE"
   SET "ID_AFFAIRE" = "OpenConcerto42"."DEVIS"."ID_AFFAIRE"
  FROM "OpenConcerto42"."TR_DEVIS"
  JOIN "OpenConcerto42"."DEVIS" ON "OpenConcerto42"."DEVIS"."ID" = "OpenConcerto42"."TR_DEVIS"."ID_DEVIS"
 WHERE "OpenConcerto42"."TR_DEVIS"."ID_SAISIE_VENTE_FACTURE" = "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" AND "OpenConcerto42"."TR_DEVIS"."ID_DEVIS" = "OpenConcerto42"."DEVIS"."ID"
   AND ("OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."DEVIS"."ID_AFFAIRE" > 1;

COMMIT;

-- DEVIS -> BON_DE_LIVRAISON

BEGIN;

UPDATE "OpenConcerto42"."BON_DE_LIVRAISON"
   SET "ID_AFFAIRE" = "OpenConcerto42"."DEVIS"."ID_AFFAIRE"
  FROM "OpenConcerto42"."TR_DEVIS"
  JOIN "OpenConcerto42"."DEVIS" ON "OpenConcerto42"."DEVIS"."ID" = "OpenConcerto42"."TR_DEVIS"."ID_DEVIS"
 WHERE "OpenConcerto42"."TR_DEVIS"."ID_BON_DE_LIVRAISON" = "OpenConcerto42"."BON_DE_LIVRAISON"."ID" AND "OpenConcerto42"."TR_DEVIS"."ID_DEVIS" = "OpenConcerto42"."DEVIS"."ID"
   AND ("OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."DEVIS"."ID_AFFAIRE" > 1;

COMMIT;

-- COMMANDE_CLIENT -> SAISIE_VENTE_FACTURE

BEGIN;

UPDATE "OpenConcerto42"."SAISIE_VENTE_FACTURE"
   SET "ID_AFFAIRE" = "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE"
  FROM "OpenConcerto42"."TR_COMMANDE_CLIENT"
  JOIN "OpenConcerto42"."COMMANDE_CLIENT" ON "OpenConcerto42"."COMMANDE_CLIENT"."ID" = "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE_CLIENT"
 WHERE "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_SAISIE_VENTE_FACTURE" = "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" AND "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE_CLIENT" = "OpenConcerto42"."COMMANDE_CLIENT"."ID"
   AND ("OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" > 1;

COMMIT;

-- COMMANDE_CLIENT -> BON_DE_LIVRAISON

BEGIN;

UPDATE "OpenConcerto42"."BON_DE_LIVRAISON"
   SET "ID_AFFAIRE" = "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE"
  FROM "OpenConcerto42"."TR_COMMANDE_CLIENT"
  JOIN "OpenConcerto42"."COMMANDE_CLIENT" ON "OpenConcerto42"."COMMANDE_CLIENT"."ID" = "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE_CLIENT"
 WHERE "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_BON_DE_LIVRAISON" = "OpenConcerto42"."BON_DE_LIVRAISON"."ID" AND "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE_CLIENT" = "OpenConcerto42"."COMMANDE_CLIENT"."ID"
   AND ("OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" > 1;

COMMIT;

-- COMMANDE_CLIENT -> COMMANDE

BEGIN;

UPDATE "OpenConcerto42"."COMMANDE"
   SET "ID_AFFAIRE" = "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE"
  FROM "OpenConcerto42"."TR_COMMANDE_CLIENT"
  JOIN "OpenConcerto42"."COMMANDE_CLIENT" ON "OpenConcerto42"."COMMANDE_CLIENT"."ID" = "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE_CLIENT"
 WHERE "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE" = "OpenConcerto42"."COMMANDE"."ID" AND "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE_CLIENT" = "OpenConcerto42"."COMMANDE_CLIENT"."ID"
   AND ("OpenConcerto42"."COMMANDE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" > 1;

COMMIT;

-- BON_DE_LIVRAISON -> SAISIE_VENTE_FACTURE

BEGIN;

UPDATE "OpenConcerto42"."SAISIE_VENTE_FACTURE"
   SET "ID_AFFAIRE" = "OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE"
  FROM "OpenConcerto42"."TR_BON_DE_LIVRAISON"
  JOIN "OpenConcerto42"."BON_DE_LIVRAISON" ON "OpenConcerto42"."BON_DE_LIVRAISON"."ID" = "OpenConcerto42"."TR_BON_DE_LIVRAISON"."ID_BON_DE_LIVRAISON"
 WHERE "OpenConcerto42"."TR_BON_DE_LIVRAISON"."ID_SAISIE_VENTE_FACTURE" = "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" AND "OpenConcerto42"."TR_BON_DE_LIVRAISON"."ID_BON_DE_LIVRAISON" = "OpenConcerto42"."BON_DE_LIVRAISON"."ID"
   AND ("OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" > 1;

COMMIT;

-- SAISIE_VENTE_FACTURE -> AVOIR_CLIENT

BEGIN;

UPDATE "OpenConcerto42"."AVOIR_CLIENT"
   SET "ID_AFFAIRE" = "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE"
  FROM "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"
  JOIN "OpenConcerto42"."SAISIE_VENTE_FACTURE" ON "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" = "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_SAISIE_VENTE_FACTURE"
 WHERE "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_AVOIR_CLIENT" = "OpenConcerto42"."AVOIR_CLIENT"."ID" AND "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_SAISIE_VENTE_FACTURE" = "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID"
   AND ("OpenConcerto42"."AVOIR_CLIENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."AVOIR_CLIENT"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" > 1;

COMMIT;

-- SAISIE_VENTE_FACTURE -> BON_DE_LIVRAISON

BEGIN;

UPDATE "OpenConcerto42"."BON_DE_LIVRAISON"
   SET "ID_AFFAIRE" = "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE"
  FROM "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"
  JOIN "OpenConcerto42"."SAISIE_VENTE_FACTURE" ON "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" = "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_SAISIE_VENTE_FACTURE"
 WHERE "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_BON_DE_LIVRAISON" = "OpenConcerto42"."BON_DE_LIVRAISON"."ID" AND "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_SAISIE_VENTE_FACTURE" = "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID"
   AND ("OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" > 1;

COMMIT;

-- SAISIE_VENTE_FACTURE -> COMMANDE

BEGIN;

UPDATE "OpenConcerto42"."COMMANDE"
   SET "ID_AFFAIRE" = "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE"
  FROM "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"
  JOIN "OpenConcerto42"."SAISIE_VENTE_FACTURE" ON "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" = "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_SAISIE_VENTE_FACTURE"
 WHERE "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_COMMANDE" = "OpenConcerto42"."COMMANDE"."ID" AND "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_SAISIE_VENTE_FACTURE" = "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID"
   AND ("OpenConcerto42"."COMMANDE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" > 1;

COMMIT;

\echo ''
\echo '=== Termine. Pour les lignes, voir sql/reprise-affaire-lignes.sql ==='
\echo 'Verifier avec sql/diagnostic-affaire-transfert.sql : les compteurs doivent etre a 0.'
