-- Diagnostic : combien de documents ont perdu leur affaire en transfert ?
--
-- Lecture seule. Aucune ecriture.
--
-- Une requete par cas : si une table n'existe pas ou n'a pas la colonne
-- attendue, psql signale CE cas et affiche les autres. Aucun compteur n'est
-- perdu a cause d'une table.
--
-- Ce fichier ne regarde que les EN-TETES de documents. Les tableaux de lignes
-- sont dans `sql/diagnostic-affaire-lignes.sql`.
--
--   sh scripts/oc-psql.sh -f sql/diagnostic-affaire-transfert.sql
--
-- Les requetes reprennent exactement les regles de AffairBackfillSupport :
-- seules les affaires VIDES (NULL) ou « Indefini » (ID 1) sont comptees, et
-- seulement quand le document source porte une vraie affaire.

\echo '=== 0. Schema utilise (adapter si votre societe porte un autre nom) ==='
select current_schema() as schema_courant;

\echo ''
\echo '=== 1. Saisies d achat sans affaire, alors que leur source en a une ==='

\echo '-- COMMANDE'
select 'SAISIE_ACHAT <- COMMANDE (SOURCE / IDSOURCE)' as cas, count(*) as documents
  from "OpenConcerto42"."SAISIE_ACHAT"
  join "OpenConcerto42"."COMMANDE" on "OpenConcerto42"."COMMANDE"."ID" = "OpenConcerto42"."SAISIE_ACHAT"."IDSOURCE"
 where "OpenConcerto42"."SAISIE_ACHAT"."SOURCE" = 'COMMANDE'
   and ("OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" > 1;

\echo '-- BON_RECEPTION'
select 'SAISIE_ACHAT <- BON_RECEPTION (SOURCE / IDSOURCE)' as cas, count(*) as documents
  from "OpenConcerto42"."SAISIE_ACHAT"
  join "OpenConcerto42"."BON_RECEPTION" on "OpenConcerto42"."BON_RECEPTION"."ID" = "OpenConcerto42"."SAISIE_ACHAT"."IDSOURCE"
 where "OpenConcerto42"."SAISIE_ACHAT"."SOURCE" = 'BON_RECEPTION'
   and ("OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" > 1;

\echo ''
\echo '=== 2. Documents sans affaire, mais leur source (table TR_*) en a une ==='

\echo '-- SAISIE_ACHAT <- COMMANDE'
select 'SAISIE_ACHAT <- COMMANDE (via TR_COMMANDE)' as cas, count(*) as documents
  from "OpenConcerto42"."SAISIE_ACHAT"
  join "OpenConcerto42"."TR_COMMANDE" on "OpenConcerto42"."TR_COMMANDE"."ID_SAISIE_ACHAT" = "OpenConcerto42"."SAISIE_ACHAT"."ID"
  join "OpenConcerto42"."COMMANDE" on "OpenConcerto42"."COMMANDE"."ID" = "OpenConcerto42"."TR_COMMANDE"."ID_COMMANDE"
 where ("OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" > 1;

\echo '-- BON_RECEPTION <- COMMANDE'
select 'BON_RECEPTION <- COMMANDE (via TR_COMMANDE)' as cas, count(*) as documents
  from "OpenConcerto42"."BON_RECEPTION"
  join "OpenConcerto42"."TR_COMMANDE" on "OpenConcerto42"."TR_COMMANDE"."ID_BON_RECEPTION" = "OpenConcerto42"."BON_RECEPTION"."ID"
  join "OpenConcerto42"."COMMANDE" on "OpenConcerto42"."COMMANDE"."ID" = "OpenConcerto42"."TR_COMMANDE"."ID_COMMANDE"
 where ("OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" > 1;

\echo '-- FACTURE_FOURNISSEUR <- COMMANDE'
select 'FACTURE_FOURNISSEUR <- COMMANDE (via TR_COMMANDE)' as cas, count(*) as documents
  from "OpenConcerto42"."FACTURE_FOURNISSEUR"
  join "OpenConcerto42"."TR_COMMANDE" on "OpenConcerto42"."TR_COMMANDE"."ID_FACTURE_FOURNISSEUR" = "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID"
  join "OpenConcerto42"."COMMANDE" on "OpenConcerto42"."COMMANDE"."ID" = "OpenConcerto42"."TR_COMMANDE"."ID_COMMANDE"
 where ("OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" > 1;

\echo '-- SAISIE_ACHAT <- BON_RECEPTION'
select 'SAISIE_ACHAT <- BON_RECEPTION (via TR_BON_RECEPTION)' as cas, count(*) as documents
  from "OpenConcerto42"."SAISIE_ACHAT"
  join "OpenConcerto42"."TR_BON_RECEPTION" on "OpenConcerto42"."TR_BON_RECEPTION"."ID_SAISIE_ACHAT" = "OpenConcerto42"."SAISIE_ACHAT"."ID"
  join "OpenConcerto42"."BON_RECEPTION" on "OpenConcerto42"."BON_RECEPTION"."ID" = "OpenConcerto42"."TR_BON_RECEPTION"."ID_BON_RECEPTION"
 where ("OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" > 1;

\echo '-- FACTURE_FOURNISSEUR <- BON_RECEPTION'
select 'FACTURE_FOURNISSEUR <- BON_RECEPTION (via TR_BON_RECEPTION)' as cas, count(*) as documents
  from "OpenConcerto42"."FACTURE_FOURNISSEUR"
  join "OpenConcerto42"."TR_BON_RECEPTION" on "OpenConcerto42"."TR_BON_RECEPTION"."ID_FACTURE_FOURNISSEUR" = "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID"
  join "OpenConcerto42"."BON_RECEPTION" on "OpenConcerto42"."BON_RECEPTION"."ID" = "OpenConcerto42"."TR_BON_RECEPTION"."ID_BON_RECEPTION"
 where ("OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" > 1;

\echo '-- COMMANDE <- DEVIS'
select 'COMMANDE <- DEVIS (via TR_DEVIS)' as cas, count(*) as documents
  from "OpenConcerto42"."COMMANDE"
  join "OpenConcerto42"."TR_DEVIS" on "OpenConcerto42"."TR_DEVIS"."ID_COMMANDE" = "OpenConcerto42"."COMMANDE"."ID"
  join "OpenConcerto42"."DEVIS" on "OpenConcerto42"."DEVIS"."ID_DEVIS" = "OpenConcerto42"."TR_DEVIS"."ID_DEVIS"
 where ("OpenConcerto42"."COMMANDE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."DEVIS"."ID_AFFAIRE" > 1;

\echo '-- AVOIR_FOURNISSEUR <- SAISIE_ACHAT'
select 'AVOIR_FOURNISSEUR <- SAISIE_ACHAT (via TR_SAISIE_ACHAT)' as cas, count(*) as documents
  from "OpenConcerto42"."AVOIR_FOURNISSEUR"
  join "OpenConcerto42"."TR_SAISIE_ACHAT" on "OpenConcerto42"."TR_SAISIE_ACHAT"."ID_AVOIR_FOURNISSEUR" = "OpenConcerto42"."AVOIR_FOURNISSEUR"."ID"
  join "OpenConcerto42"."SAISIE_ACHAT" on "OpenConcerto42"."SAISIE_ACHAT"."ID" = "OpenConcerto42"."TR_SAISIE_ACHAT"."ID_SAISIE_ACHAT"
 where ("OpenConcerto42"."AVOIR_FOURNISSEUR"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."AVOIR_FOURNISSEUR"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" > 1;

\echo '-- COMMANDE_CLIENT <- DEVIS'
select 'COMMANDE_CLIENT <- DEVIS (via TR_DEVIS)' as cas, count(*) as documents
  from "OpenConcerto42"."COMMANDE_CLIENT"
  join "OpenConcerto42"."TR_DEVIS" on "OpenConcerto42"."TR_DEVIS"."ID_COMMANDE_CLIENT" = "OpenConcerto42"."COMMANDE_CLIENT"."ID"
  join "OpenConcerto42"."DEVIS" on "OpenConcerto42"."DEVIS"."ID_DEVIS" = "OpenConcerto42"."TR_DEVIS"."ID_DEVIS"
 where ("OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."DEVIS"."ID_AFFAIRE" > 1;

\echo '-- SAISIE_VENTE_FACTURE <- DEVIS'
select 'SAISIE_VENTE_FACTURE <- DEVIS (via TR_DEVIS)' as cas, count(*) as documents
  from "OpenConcerto42"."SAISIE_VENTE_FACTURE"
  join "OpenConcerto42"."TR_DEVIS" on "OpenConcerto42"."TR_DEVIS"."ID_SAISIE_VENTE_FACTURE" = "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID"
  join "OpenConcerto42"."DEVIS" on "OpenConcerto42"."DEVIS"."ID_DEVIS" = "OpenConcerto42"."TR_DEVIS"."ID_DEVIS"
 where ("OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."DEVIS"."ID_AFFAIRE" > 1;

\echo '-- BON_DE_LIVRAISON <- DEVIS'
select 'BON_DE_LIVRAISON <- DEVIS (via TR_DEVIS)' as cas, count(*) as documents
  from "OpenConcerto42"."BON_DE_LIVRAISON"
  join "OpenConcerto42"."TR_DEVIS" on "OpenConcerto42"."TR_DEVIS"."ID_BON_DE_LIVRAISON" = "OpenConcerto42"."BON_DE_LIVRAISON"."ID"
  join "OpenConcerto42"."DEVIS" on "OpenConcerto42"."DEVIS"."ID_DEVIS" = "OpenConcerto42"."TR_DEVIS"."ID_DEVIS"
 where ("OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."DEVIS"."ID_AFFAIRE" > 1;

\echo '-- SAISIE_VENTE_FACTURE <- COMMANDE_CLIENT'
select 'SAISIE_VENTE_FACTURE <- COMMANDE_CLIENT (via TR_COMMANDE_CLIENT)' as cas, count(*) as documents
  from "OpenConcerto42"."SAISIE_VENTE_FACTURE"
  join "OpenConcerto42"."TR_COMMANDE_CLIENT" on "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_SAISIE_VENTE_FACTURE" = "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID"
  join "OpenConcerto42"."COMMANDE_CLIENT" on "OpenConcerto42"."COMMANDE_CLIENT"."ID" = "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE_CLIENT"
 where ("OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" > 1;

\echo '-- BON_DE_LIVRAISON <- COMMANDE_CLIENT'
select 'BON_DE_LIVRAISON <- COMMANDE_CLIENT (via TR_COMMANDE_CLIENT)' as cas, count(*) as documents
  from "OpenConcerto42"."BON_DE_LIVRAISON"
  join "OpenConcerto42"."TR_COMMANDE_CLIENT" on "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_BON_DE_LIVRAISON" = "OpenConcerto42"."BON_DE_LIVRAISON"."ID"
  join "OpenConcerto42"."COMMANDE_CLIENT" on "OpenConcerto42"."COMMANDE_CLIENT"."ID" = "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE_CLIENT"
 where ("OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" > 1;

\echo '-- COMMANDE <- COMMANDE_CLIENT'
select 'COMMANDE <- COMMANDE_CLIENT (via TR_COMMANDE_CLIENT)' as cas, count(*) as documents
  from "OpenConcerto42"."COMMANDE"
  join "OpenConcerto42"."TR_COMMANDE_CLIENT" on "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE" = "OpenConcerto42"."COMMANDE"."ID"
  join "OpenConcerto42"."COMMANDE_CLIENT" on "OpenConcerto42"."COMMANDE_CLIENT"."ID" = "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE_CLIENT"
 where ("OpenConcerto42"."COMMANDE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" > 1;

\echo '-- SAISIE_VENTE_FACTURE <- BON_DE_LIVRAISON'
select 'SAISIE_VENTE_FACTURE <- BON_DE_LIVRAISON (via TR_BON_DE_LIVRAISON)' as cas, count(*) as documents
  from "OpenConcerto42"."SAISIE_VENTE_FACTURE"
  join "OpenConcerto42"."TR_BON_DE_LIVRAISON" on "OpenConcerto42"."TR_BON_DE_LIVRAISON"."ID_SAISIE_VENTE_FACTURE" = "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID"
  join "OpenConcerto42"."BON_DE_LIVRAISON" on "OpenConcerto42"."BON_DE_LIVRAISON"."ID" = "OpenConcerto42"."TR_BON_DE_LIVRAISON"."ID_BON_DE_LIVRAISON"
 where ("OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" > 1;

\echo '-- AVOIR_CLIENT <- SAISIE_VENTE_FACTURE'
select 'AVOIR_CLIENT <- SAISIE_VENTE_FACTURE (via TR_SAISIE_VENTE_FACTURE)' as cas, count(*) as documents
  from "OpenConcerto42"."AVOIR_CLIENT"
  join "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE" on "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_AVOIR_CLIENT" = "OpenConcerto42"."AVOIR_CLIENT"."ID"
  join "OpenConcerto42"."SAISIE_VENTE_FACTURE" on "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" = "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_SAISIE_VENTE_FACTURE"
 where ("OpenConcerto42"."AVOIR_CLIENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."AVOIR_CLIENT"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" > 1;

\echo '-- BON_DE_LIVRAISON <- SAISIE_VENTE_FACTURE'
select 'BON_DE_LIVRAISON <- SAISIE_VENTE_FACTURE (via TR_SAISIE_VENTE_FACTURE)' as cas, count(*) as documents
  from "OpenConcerto42"."BON_DE_LIVRAISON"
  join "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE" on "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_BON_DE_LIVRAISON" = "OpenConcerto42"."BON_DE_LIVRAISON"."ID"
  join "OpenConcerto42"."SAISIE_VENTE_FACTURE" on "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" = "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_SAISIE_VENTE_FACTURE"
 where ("OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" > 1;

\echo '-- COMMANDE <- SAISIE_VENTE_FACTURE'
select 'COMMANDE <- SAISIE_VENTE_FACTURE (via TR_SAISIE_VENTE_FACTURE)' as cas, count(*) as documents
  from "OpenConcerto42"."COMMANDE"
  join "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE" on "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_COMMANDE" = "OpenConcerto42"."COMMANDE"."ID"
  join "OpenConcerto42"."SAISIE_VENTE_FACTURE" on "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" = "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_SAISIE_VENTE_FACTURE"
 where ("OpenConcerto42"."COMMANDE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" > 1;


\echo ''
\echo '=== 3. Tableaux de lignes qui portent la colonne ID_AFFAIRE ==='
\echo '(les autres lisent l affaire de leur document : rien a reprendre chez eux)'
select table_name as table_lignes
  from information_schema.columns
 where table_schema = 'OpenConcerto42' and column_name = 'ID_AFFAIRE'
   and table_name like '%_ELEMENT'
 order by 1;

\echo ''
\echo '=== 4. Les tables de transfert presentes dans cette base ==='
select table_name
  from information_schema.tables
 where table_schema = 'OpenConcerto42' and table_name like 'TR%'
 order by 1;

\echo ''
\echo '=== 5. Rappel : documents sans affaire, tous cas confondus ==='

select 'AVOIR_CLIENT' as document, count(*) as sans_affaire from "OpenConcerto42"."AVOIR_CLIENT" where ("OpenConcerto42"."AVOIR_CLIENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."AVOIR_CLIENT"."ID_AFFAIRE" = 1);
select 'AVOIR_FOURNISSEUR' as document, count(*) as sans_affaire from "OpenConcerto42"."AVOIR_FOURNISSEUR" where ("OpenConcerto42"."AVOIR_FOURNISSEUR"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."AVOIR_FOURNISSEUR"."ID_AFFAIRE" = 1);
select 'BON_DE_LIVRAISON' as document, count(*) as sans_affaire from "OpenConcerto42"."BON_DE_LIVRAISON" where ("OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" = 1);
select 'BON_RECEPTION' as document, count(*) as sans_affaire from "OpenConcerto42"."BON_RECEPTION" where ("OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" = 1);
select 'COMMANDE' as document, count(*) as sans_affaire from "OpenConcerto42"."COMMANDE" where ("OpenConcerto42"."COMMANDE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" = 1);
select 'COMMANDE_CLIENT' as document, count(*) as sans_affaire from "OpenConcerto42"."COMMANDE_CLIENT" where ("OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" = 1);
select 'DEVIS' as document, count(*) as sans_affaire from "OpenConcerto42"."DEVIS" where ("OpenConcerto42"."DEVIS"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."DEVIS"."ID_AFFAIRE" = 1);
select 'FACTURE_FOURNISSEUR' as document, count(*) as sans_affaire from "OpenConcerto42"."FACTURE_FOURNISSEUR" where ("OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" = 1);
select 'SAISIE_ACHAT' as document, count(*) as sans_affaire from "OpenConcerto42"."SAISIE_ACHAT" where ("OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" = 1);
select 'SAISIE_VENTE_FACTURE' as document, count(*) as sans_affaire from "OpenConcerto42"."SAISIE_VENTE_FACTURE" where ("OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" = 1);
