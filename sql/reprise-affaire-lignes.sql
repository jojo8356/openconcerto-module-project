-- Reprise des affaires sur les TABLEAUX DE LIGNES (fichier a part).
--
-- Pourquoi a part : sur la base du client, seuls FACTURE_FOURNISSEUR_ELEMENT et
-- DEMANDE_ACHAT_ELEMENT portent la colonne ID_AFFAIRE ; les dix autres tableaux
-- ne l'ont pas. Un UPDATE sur une table sans la colonne fait echouer toute la
-- transaction, donc les en-tetes de `reprise-affaire-transfert.sql` seraient
-- annules en meme temps. Ici, chaque bloc est independant : executez ceux que
-- la requete ci-dessous autorise.
--
--   sh scripts/oc-psql.sh -f sql/reprise-affaire-lignes.sql
--
-- Regle identique au module : on ne remplit que le vide (NULL ou « Indefini »),
-- et seulement si le document porte une vraie affaire. Idempotent.

\echo '=== 0. Tableaux de lignes qui portent reellement ID_AFFAIRE ==='
\echo '(executez seulement les blocs correspondants, ci-dessous)'
select table_name
  from information_schema.columns
 where table_schema = 'OpenConcerto42' and column_name = 'ID_AFFAIRE'
   and table_name like '%_ELEMENT'
 order by 1;


-- COMMANDE_ELEMENT (colonne ID_AFFAIRE requise)

BEGIN;

UPDATE "OpenConcerto42"."COMMANDE_ELEMENT"
   SET "ID_AFFAIRE" = "OpenConcerto42"."COMMANDE"."ID_AFFAIRE"
  FROM "OpenConcerto42"."COMMANDE"
 WHERE "OpenConcerto42"."COMMANDE_ELEMENT"."ID_COMMANDE" = "OpenConcerto42"."COMMANDE"."ID"
   AND ("OpenConcerto42"."COMMANDE_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE_ELEMENT"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" > 1;

COMMIT;


-- FACTURE_FOURNISSEUR_ELEMENT (colonne ID_AFFAIRE requise)

BEGIN;

UPDATE "OpenConcerto42"."FACTURE_FOURNISSEUR_ELEMENT"
   SET "ID_AFFAIRE" = "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE"
  FROM "OpenConcerto42"."FACTURE_FOURNISSEUR"
 WHERE "OpenConcerto42"."FACTURE_FOURNISSEUR_ELEMENT"."ID_FACTURE_FOURNISSEUR" = "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID"
   AND ("OpenConcerto42"."FACTURE_FOURNISSEUR_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."FACTURE_FOURNISSEUR_ELEMENT"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" > 1;

COMMIT;


-- BON_RECEPTION_ELEMENT (colonne ID_AFFAIRE requise)

BEGIN;

UPDATE "OpenConcerto42"."BON_RECEPTION_ELEMENT"
   SET "ID_AFFAIRE" = "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE"
  FROM "OpenConcerto42"."BON_RECEPTION"
 WHERE "OpenConcerto42"."BON_RECEPTION_ELEMENT"."ID_BON_RECEPTION" = "OpenConcerto42"."BON_RECEPTION"."ID"
   AND ("OpenConcerto42"."BON_RECEPTION_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_RECEPTION_ELEMENT"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" > 1;

COMMIT;


-- DEMANDE_PRIX_ELEMENT (colonne ID_AFFAIRE requise)

BEGIN;

UPDATE "OpenConcerto42"."DEMANDE_PRIX_ELEMENT"
   SET "ID_AFFAIRE" = "OpenConcerto42"."DEMANDE_PRIX"."ID_AFFAIRE"
  FROM "OpenConcerto42"."DEMANDE_PRIX"
 WHERE "OpenConcerto42"."DEMANDE_PRIX_ELEMENT"."ID_DEMANDE_PRIX" = "OpenConcerto42"."DEMANDE_PRIX"."ID"
   AND ("OpenConcerto42"."DEMANDE_PRIX_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."DEMANDE_PRIX_ELEMENT"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."DEMANDE_PRIX"."ID_AFFAIRE" > 1;

COMMIT;


-- DEMANDE_ACHAT_ELEMENT (colonne ID_AFFAIRE requise)

BEGIN;

UPDATE "OpenConcerto42"."DEMANDE_ACHAT_ELEMENT"
   SET "ID_AFFAIRE" = "OpenConcerto42"."DEMANDE_ACHAT"."ID_AFFAIRE"
  FROM "OpenConcerto42"."DEMANDE_ACHAT"
 WHERE "OpenConcerto42"."DEMANDE_ACHAT_ELEMENT"."ID_DEMANDE_ACHAT" = "OpenConcerto42"."DEMANDE_ACHAT"."ID"
   AND ("OpenConcerto42"."DEMANDE_ACHAT_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."DEMANDE_ACHAT_ELEMENT"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."DEMANDE_ACHAT"."ID_AFFAIRE" > 1;

COMMIT;


-- SAISIE_ACHAT_ELEMENT (colonne ID_AFFAIRE requise)

BEGIN;

UPDATE "OpenConcerto42"."SAISIE_ACHAT_ELEMENT"
   SET "ID_AFFAIRE" = "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE"
  FROM "OpenConcerto42"."SAISIE_ACHAT"
 WHERE "OpenConcerto42"."SAISIE_ACHAT_ELEMENT"."ID_SAISIE_ACHAT" = "OpenConcerto42"."SAISIE_ACHAT"."ID"
   AND ("OpenConcerto42"."SAISIE_ACHAT_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_ACHAT_ELEMENT"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" > 1;

COMMIT;


-- AVOIR_FOURNISSEUR_ELEMENT (colonne ID_AFFAIRE requise)

BEGIN;

UPDATE "OpenConcerto42"."AVOIR_FOURNISSEUR_ELEMENT"
   SET "ID_AFFAIRE" = "OpenConcerto42"."AVOIR_FOURNISSEUR"."ID_AFFAIRE"
  FROM "OpenConcerto42"."AVOIR_FOURNISSEUR"
 WHERE "OpenConcerto42"."AVOIR_FOURNISSEUR_ELEMENT"."ID_AVOIR_FOURNISSEUR" = "OpenConcerto42"."AVOIR_FOURNISSEUR"."ID"
   AND ("OpenConcerto42"."AVOIR_FOURNISSEUR_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."AVOIR_FOURNISSEUR_ELEMENT"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."AVOIR_FOURNISSEUR"."ID_AFFAIRE" > 1;

COMMIT;


-- COMMANDE_CLIENT_ELEMENT (colonne ID_AFFAIRE requise)

BEGIN;

UPDATE "OpenConcerto42"."COMMANDE_CLIENT_ELEMENT"
   SET "ID_AFFAIRE" = "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE"
  FROM "OpenConcerto42"."COMMANDE_CLIENT"
 WHERE "OpenConcerto42"."COMMANDE_CLIENT_ELEMENT"."ID_COMMANDE_CLIENT" = "OpenConcerto42"."COMMANDE_CLIENT"."ID"
   AND ("OpenConcerto42"."COMMANDE_CLIENT_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE_CLIENT_ELEMENT"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" > 1;

COMMIT;


-- SAISIE_VENTE_FACTURE_ELEMENT (colonne ID_AFFAIRE requise)

BEGIN;

UPDATE "OpenConcerto42"."SAISIE_VENTE_FACTURE_ELEMENT"
   SET "ID_AFFAIRE" = "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE"
  FROM "OpenConcerto42"."SAISIE_VENTE_FACTURE"
 WHERE "OpenConcerto42"."SAISIE_VENTE_FACTURE_ELEMENT"."ID_SAISIE_VENTE_FACTURE" = "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID"
   AND ("OpenConcerto42"."SAISIE_VENTE_FACTURE_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_VENTE_FACTURE_ELEMENT"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" > 1;

COMMIT;


-- DEVIS_ELEMENT (colonne ID_AFFAIRE requise)

BEGIN;

UPDATE "OpenConcerto42"."DEVIS_ELEMENT"
   SET "ID_AFFAIRE" = "OpenConcerto42"."DEVIS"."ID_AFFAIRE"
  FROM "OpenConcerto42"."DEVIS"
 WHERE "OpenConcerto42"."DEVIS_ELEMENT"."ID_DEVIS" = "OpenConcerto42"."DEVIS"."ID_DEVIS"
   AND ("OpenConcerto42"."DEVIS_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."DEVIS_ELEMENT"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."DEVIS"."ID_AFFAIRE" > 1;

COMMIT;


-- AVOIR_CLIENT_ELEMENT (colonne ID_AFFAIRE requise)

BEGIN;

UPDATE "OpenConcerto42"."AVOIR_CLIENT_ELEMENT"
   SET "ID_AFFAIRE" = "OpenConcerto42"."AVOIR_CLIENT"."ID_AFFAIRE"
  FROM "OpenConcerto42"."AVOIR_CLIENT"
 WHERE "OpenConcerto42"."AVOIR_CLIENT_ELEMENT"."ID_AVOIR_CLIENT" = "OpenConcerto42"."AVOIR_CLIENT"."ID"
   AND ("OpenConcerto42"."AVOIR_CLIENT_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."AVOIR_CLIENT_ELEMENT"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."AVOIR_CLIENT"."ID_AFFAIRE" > 1;

COMMIT;


-- BON_DE_LIVRAISON_ELEMENT (colonne ID_AFFAIRE requise)

BEGIN;

UPDATE "OpenConcerto42"."BON_DE_LIVRAISON_ELEMENT"
   SET "ID_AFFAIRE" = "OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE"
  FROM "OpenConcerto42"."BON_DE_LIVRAISON"
 WHERE "OpenConcerto42"."BON_DE_LIVRAISON_ELEMENT"."ID_BON_DE_LIVRAISON" = "OpenConcerto42"."BON_DE_LIVRAISON"."ID"
   AND ("OpenConcerto42"."BON_DE_LIVRAISON_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_DE_LIVRAISON_ELEMENT"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" > 1;

COMMIT;

\echo ''
\echo '=== Termine. Chaque bloc est dans sa propre transaction : un tableau sans la'
\echo 'colonne n''annule pas les autres. ==='
