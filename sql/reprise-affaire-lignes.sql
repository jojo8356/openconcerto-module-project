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


\echo '--- 1/12 COMMANDE_ELEMENT (lignes de COMMANDE) ---'


-- COMMANDE_ELEMENT (colonne ID_AFFAIRE requise : si elle n existe pas, PostgreSQL repond
-- « column ... does not exist », le bloc est annule et le suivant continue)

BEGIN;

UPDATE "OpenConcerto42"."COMMANDE_ELEMENT"
   SET "ID_AFFAIRE" = "OpenConcerto42"."COMMANDE"."ID_AFFAIRE"
  FROM "OpenConcerto42"."COMMANDE"
 WHERE "OpenConcerto42"."COMMANDE_ELEMENT"."ID_COMMANDE" = "OpenConcerto42"."COMMANDE"."ID"
   AND ("OpenConcerto42"."COMMANDE_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE_ELEMENT"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" > 1
   AND "OpenConcerto42"."COMMANDE_ELEMENT"."ID_COMMANDE" > 1 AND "OpenConcerto42"."COMMANDE"."ID" > 1;

COMMIT;


\echo '--- 2/12 FACTURE_FOURNISSEUR_ELEMENT (lignes de FACTURE_FOURNISSEUR) ---'


-- FACTURE_FOURNISSEUR_ELEMENT (colonne ID_AFFAIRE requise : si elle n existe pas, PostgreSQL repond
-- « column ... does not exist », le bloc est annule et le suivant continue)

BEGIN;

UPDATE "OpenConcerto42"."FACTURE_FOURNISSEUR_ELEMENT"
   SET "ID_AFFAIRE" = "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE"
  FROM "OpenConcerto42"."FACTURE_FOURNISSEUR"
 WHERE "OpenConcerto42"."FACTURE_FOURNISSEUR_ELEMENT"."ID_FACTURE_FOURNISSEUR" = "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID"
   AND ("OpenConcerto42"."FACTURE_FOURNISSEUR_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."FACTURE_FOURNISSEUR_ELEMENT"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" > 1
   AND "OpenConcerto42"."FACTURE_FOURNISSEUR_ELEMENT"."ID_FACTURE_FOURNISSEUR" > 1 AND "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID" > 1;

COMMIT;


\echo '--- 3/12 BON_RECEPTION_ELEMENT (lignes de BON_RECEPTION) ---'


-- BON_RECEPTION_ELEMENT (colonne ID_AFFAIRE requise : si elle n existe pas, PostgreSQL repond
-- « column ... does not exist », le bloc est annule et le suivant continue)

BEGIN;

UPDATE "OpenConcerto42"."BON_RECEPTION_ELEMENT"
   SET "ID_AFFAIRE" = "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE"
  FROM "OpenConcerto42"."BON_RECEPTION"
 WHERE "OpenConcerto42"."BON_RECEPTION_ELEMENT"."ID_BON_RECEPTION" = "OpenConcerto42"."BON_RECEPTION"."ID"
   AND ("OpenConcerto42"."BON_RECEPTION_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_RECEPTION_ELEMENT"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" > 1
   AND "OpenConcerto42"."BON_RECEPTION_ELEMENT"."ID_BON_RECEPTION" > 1 AND "OpenConcerto42"."BON_RECEPTION"."ID" > 1;

COMMIT;


\echo '--- 4/12 DEMANDE_PRIX_ELEMENT (lignes de DEMANDE_PRIX) ---'


-- DEMANDE_PRIX_ELEMENT (colonne ID_AFFAIRE requise : si elle n existe pas, PostgreSQL repond
-- « column ... does not exist », le bloc est annule et le suivant continue)

BEGIN;

UPDATE "OpenConcerto42"."DEMANDE_PRIX_ELEMENT"
   SET "ID_AFFAIRE" = "OpenConcerto42"."DEMANDE_PRIX"."ID_AFFAIRE"
  FROM "OpenConcerto42"."DEMANDE_PRIX"
 WHERE "OpenConcerto42"."DEMANDE_PRIX_ELEMENT"."ID_DEMANDE_PRIX" = "OpenConcerto42"."DEMANDE_PRIX"."ID"
   AND ("OpenConcerto42"."DEMANDE_PRIX_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."DEMANDE_PRIX_ELEMENT"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."DEMANDE_PRIX"."ID_AFFAIRE" > 1
   AND "OpenConcerto42"."DEMANDE_PRIX_ELEMENT"."ID_DEMANDE_PRIX" > 1 AND "OpenConcerto42"."DEMANDE_PRIX"."ID" > 1;

COMMIT;


\echo '--- 5/12 DEMANDE_ACHAT_ELEMENT (lignes de DEMANDE_ACHAT) ---'


-- DEMANDE_ACHAT_ELEMENT (colonne ID_AFFAIRE requise : si elle n existe pas, PostgreSQL repond
-- « column ... does not exist », le bloc est annule et le suivant continue)

BEGIN;

UPDATE "OpenConcerto42"."DEMANDE_ACHAT_ELEMENT"
   SET "ID_AFFAIRE" = "OpenConcerto42"."DEMANDE_ACHAT"."ID_AFFAIRE"
  FROM "OpenConcerto42"."DEMANDE_ACHAT"
 WHERE "OpenConcerto42"."DEMANDE_ACHAT_ELEMENT"."ID_DEMANDE_ACHAT" = "OpenConcerto42"."DEMANDE_ACHAT"."ID"
   AND ("OpenConcerto42"."DEMANDE_ACHAT_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."DEMANDE_ACHAT_ELEMENT"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."DEMANDE_ACHAT"."ID_AFFAIRE" > 1
   AND "OpenConcerto42"."DEMANDE_ACHAT_ELEMENT"."ID_DEMANDE_ACHAT" > 1 AND "OpenConcerto42"."DEMANDE_ACHAT"."ID" > 1;

COMMIT;


\echo '--- 6/12 SAISIE_ACHAT_ELEMENT (lignes de SAISIE_ACHAT) ---'


-- SAISIE_ACHAT_ELEMENT (colonne ID_AFFAIRE requise : si elle n existe pas, PostgreSQL repond
-- « column ... does not exist », le bloc est annule et le suivant continue)

BEGIN;

UPDATE "OpenConcerto42"."SAISIE_ACHAT_ELEMENT"
   SET "ID_AFFAIRE" = "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE"
  FROM "OpenConcerto42"."SAISIE_ACHAT"
 WHERE "OpenConcerto42"."SAISIE_ACHAT_ELEMENT"."ID_SAISIE_ACHAT" = "OpenConcerto42"."SAISIE_ACHAT"."ID"
   AND ("OpenConcerto42"."SAISIE_ACHAT_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_ACHAT_ELEMENT"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" > 1
   AND "OpenConcerto42"."SAISIE_ACHAT_ELEMENT"."ID_SAISIE_ACHAT" > 1 AND "OpenConcerto42"."SAISIE_ACHAT"."ID" > 1;

COMMIT;


\echo '--- 7/12 AVOIR_FOURNISSEUR_ELEMENT (lignes de AVOIR_FOURNISSEUR) ---'


-- AVOIR_FOURNISSEUR_ELEMENT (colonne ID_AFFAIRE requise : si elle n existe pas, PostgreSQL repond
-- « column ... does not exist », le bloc est annule et le suivant continue)

BEGIN;

UPDATE "OpenConcerto42"."AVOIR_FOURNISSEUR_ELEMENT"
   SET "ID_AFFAIRE" = "OpenConcerto42"."AVOIR_FOURNISSEUR"."ID_AFFAIRE"
  FROM "OpenConcerto42"."AVOIR_FOURNISSEUR"
 WHERE "OpenConcerto42"."AVOIR_FOURNISSEUR_ELEMENT"."ID_AVOIR_FOURNISSEUR" = "OpenConcerto42"."AVOIR_FOURNISSEUR"."ID"
   AND ("OpenConcerto42"."AVOIR_FOURNISSEUR_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."AVOIR_FOURNISSEUR_ELEMENT"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."AVOIR_FOURNISSEUR"."ID_AFFAIRE" > 1
   AND "OpenConcerto42"."AVOIR_FOURNISSEUR_ELEMENT"."ID_AVOIR_FOURNISSEUR" > 1 AND "OpenConcerto42"."AVOIR_FOURNISSEUR"."ID" > 1;

COMMIT;


\echo '--- 8/12 COMMANDE_CLIENT_ELEMENT (lignes de COMMANDE_CLIENT) ---'


-- COMMANDE_CLIENT_ELEMENT (colonne ID_AFFAIRE requise : si elle n existe pas, PostgreSQL repond
-- « column ... does not exist », le bloc est annule et le suivant continue)

BEGIN;

UPDATE "OpenConcerto42"."COMMANDE_CLIENT_ELEMENT"
   SET "ID_AFFAIRE" = "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE"
  FROM "OpenConcerto42"."COMMANDE_CLIENT"
 WHERE "OpenConcerto42"."COMMANDE_CLIENT_ELEMENT"."ID_COMMANDE_CLIENT" = "OpenConcerto42"."COMMANDE_CLIENT"."ID"
   AND ("OpenConcerto42"."COMMANDE_CLIENT_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE_CLIENT_ELEMENT"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" > 1
   AND "OpenConcerto42"."COMMANDE_CLIENT_ELEMENT"."ID_COMMANDE_CLIENT" > 1 AND "OpenConcerto42"."COMMANDE_CLIENT"."ID" > 1;

COMMIT;


\echo '--- 9/12 SAISIE_VENTE_FACTURE_ELEMENT (lignes de SAISIE_VENTE_FACTURE) ---'


-- SAISIE_VENTE_FACTURE_ELEMENT (colonne ID_AFFAIRE requise : si elle n existe pas, PostgreSQL repond
-- « column ... does not exist », le bloc est annule et le suivant continue)

BEGIN;

UPDATE "OpenConcerto42"."SAISIE_VENTE_FACTURE_ELEMENT"
   SET "ID_AFFAIRE" = "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE"
  FROM "OpenConcerto42"."SAISIE_VENTE_FACTURE"
 WHERE "OpenConcerto42"."SAISIE_VENTE_FACTURE_ELEMENT"."ID_SAISIE_VENTE_FACTURE" = "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID"
   AND ("OpenConcerto42"."SAISIE_VENTE_FACTURE_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_VENTE_FACTURE_ELEMENT"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" > 1
   AND "OpenConcerto42"."SAISIE_VENTE_FACTURE_ELEMENT"."ID_SAISIE_VENTE_FACTURE" > 1 AND "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" > 1;

COMMIT;


\echo '--- 10/12 DEVIS_ELEMENT (lignes de DEVIS) ---'


-- DEVIS_ELEMENT (colonne ID_AFFAIRE requise : si elle n existe pas, PostgreSQL repond
-- « column ... does not exist », le bloc est annule et le suivant continue)

BEGIN;

UPDATE "OpenConcerto42"."DEVIS_ELEMENT"
   SET "ID_AFFAIRE" = "OpenConcerto42"."DEVIS"."ID_AFFAIRE"
  FROM "OpenConcerto42"."DEVIS"
 WHERE "OpenConcerto42"."DEVIS_ELEMENT"."ID_DEVIS" = "OpenConcerto42"."DEVIS"."ID_DEVIS"
   AND ("OpenConcerto42"."DEVIS_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."DEVIS_ELEMENT"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."DEVIS"."ID_AFFAIRE" > 1
   AND "OpenConcerto42"."DEVIS_ELEMENT"."ID_DEVIS" > 1 AND "OpenConcerto42"."DEVIS"."ID_DEVIS" > 1;

COMMIT;


\echo '--- 11/12 AVOIR_CLIENT_ELEMENT (lignes de AVOIR_CLIENT) ---'


-- AVOIR_CLIENT_ELEMENT (colonne ID_AFFAIRE requise : si elle n existe pas, PostgreSQL repond
-- « column ... does not exist », le bloc est annule et le suivant continue)

BEGIN;

UPDATE "OpenConcerto42"."AVOIR_CLIENT_ELEMENT"
   SET "ID_AFFAIRE" = "OpenConcerto42"."AVOIR_CLIENT"."ID_AFFAIRE"
  FROM "OpenConcerto42"."AVOIR_CLIENT"
 WHERE "OpenConcerto42"."AVOIR_CLIENT_ELEMENT"."ID_AVOIR_CLIENT" = "OpenConcerto42"."AVOIR_CLIENT"."ID"
   AND ("OpenConcerto42"."AVOIR_CLIENT_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."AVOIR_CLIENT_ELEMENT"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."AVOIR_CLIENT"."ID_AFFAIRE" > 1
   AND "OpenConcerto42"."AVOIR_CLIENT_ELEMENT"."ID_AVOIR_CLIENT" > 1 AND "OpenConcerto42"."AVOIR_CLIENT"."ID" > 1;

COMMIT;


\echo '--- 12/12 BON_DE_LIVRAISON_ELEMENT (lignes de BON_DE_LIVRAISON) ---'


-- BON_DE_LIVRAISON_ELEMENT (colonne ID_AFFAIRE requise : si elle n existe pas, PostgreSQL repond
-- « column ... does not exist », le bloc est annule et le suivant continue)

BEGIN;

UPDATE "OpenConcerto42"."BON_DE_LIVRAISON_ELEMENT"
   SET "ID_AFFAIRE" = "OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE"
  FROM "OpenConcerto42"."BON_DE_LIVRAISON"
 WHERE "OpenConcerto42"."BON_DE_LIVRAISON_ELEMENT"."ID_BON_DE_LIVRAISON" = "OpenConcerto42"."BON_DE_LIVRAISON"."ID"
   AND ("OpenConcerto42"."BON_DE_LIVRAISON_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_DE_LIVRAISON_ELEMENT"."ID_AFFAIRE" = 1)
   AND "OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" > 1
   AND "OpenConcerto42"."BON_DE_LIVRAISON_ELEMENT"."ID_BON_DE_LIVRAISON" > 1 AND "OpenConcerto42"."BON_DE_LIVRAISON"."ID" > 1;

COMMIT;

\echo ''
\echo '=== Tableaux sans la colonne (blocs annules : c est normal) ==='
select count(*) as tableaux_de_lignes_sans_colonne
  from information_schema.tables tb
 where tb.table_schema = 'OpenConcerto42' and tb.table_name in ('COMMANDE_ELEMENT', 'FACTURE_FOURNISSEUR_ELEMENT', 'BON_RECEPTION_ELEMENT', 'DEMANDE_PRIX_ELEMENT', 'DEMANDE_ACHAT_ELEMENT', 'SAISIE_ACHAT_ELEMENT', 'AVOIR_FOURNISSEUR_ELEMENT', 'COMMANDE_CLIENT_ELEMENT', 'SAISIE_VENTE_FACTURE_ELEMENT', 'DEVIS_ELEMENT', 'AVOIR_CLIENT_ELEMENT', 'BON_DE_LIVRAISON_ELEMENT')
   and not exists (select 1 from information_schema.columns co
                    where co.table_schema = tb.table_schema and co.table_name = tb.table_name
                      and co.column_name = 'ID_AFFAIRE');

\echo ''
\echo '=== Termine. Chaque bloc est dans une transaction : un tableau sans la'
\echo 'colonne n''annule pas les autres. ==='
