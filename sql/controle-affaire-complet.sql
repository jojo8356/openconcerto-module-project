-- Controle complet du rattachement d'affaire : tout ce qui a ete corrige.
--
-- Lecture seule. AUCUNE ECRITURE : ce fichier ne repare rien, il verifie.
--
-- Il reprend les requetes des autres fichiers (memes regles, meme generateur) et
-- les regroupe dans l'ordre du diagnostic. Apres une reprise, les sections 1, 4
-- et 6 doivent etre a 0.
--
--   sh scripts/oc-psql.sh -f sql/controle-affaire-complet.sql
--
-- Les trois defauts que ces requetes detectent (mesures sur la base du client) :
--   * une cle etrangere non renseignee vaut 1, pas NULL : sans le garde-fou
--     « <cle> > 1 », la ligne « Indefini » est comptee 200 fois ;
--   * DEVIS n'a pas de colonne ID : sa cle est ID_DEVIS ;
--   * les tableaux de lignes n'ont pas tous la colonne ID_AFFAIRE (2 sur 12) :
--     pour ceux qui ne l'ont pas, la section 4 affiche une erreur « column does
--     not exist » et psql CONTINUE avec les autres tableaux — c'est normal,
--     chaque bloc est independant.


\echo '################################################################'
\echo '# 0. Schema : les cles et les colonnes que les requetes supposent'
\echo '################################################################'

\echo '--- 0.1 Schema courant ---'
select current_schema() as schema_courant;

\echo '--- 0.2 Cle de DEVIS (ID attendu ; ID_DEVIS sur la base du client) ---'
select column_name
  from information_schema.columns
 where table_schema = 'OpenConcerto42' and table_name = 'DEVIS' and column_name in ('ID', 'ID_DEVIS')
 order by 1;

\echo '--- 0.3 Tables d en-tete qui portent la colonne ID_AFFAIRE ---'
select table_name
  from information_schema.columns
 where table_schema = 'OpenConcerto42' and column_name = 'ID_AFFAIRE'
 order by 1;


\echo '################################################################'
\echo '# 1. Documents a reprendre, cas par cas (attendu : 0 partout)'
\echo '################################################################'

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
   and "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" > 1
   and "OpenConcerto42"."SAISIE_ACHAT"."IDSOURCE" > 1
   and "OpenConcerto42"."SAISIE_ACHAT"."ID" > 1 and "OpenConcerto42"."COMMANDE"."ID" > 1;

\echo '-- BON_RECEPTION'
select 'SAISIE_ACHAT <- BON_RECEPTION (SOURCE / IDSOURCE)' as cas, count(*) as documents
  from "OpenConcerto42"."SAISIE_ACHAT"
  join "OpenConcerto42"."BON_RECEPTION" on "OpenConcerto42"."BON_RECEPTION"."ID" = "OpenConcerto42"."SAISIE_ACHAT"."IDSOURCE"
 where "OpenConcerto42"."SAISIE_ACHAT"."SOURCE" = 'BON_RECEPTION'
   and ("OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" > 1
   and "OpenConcerto42"."SAISIE_ACHAT"."IDSOURCE" > 1
   and "OpenConcerto42"."SAISIE_ACHAT"."ID" > 1 and "OpenConcerto42"."BON_RECEPTION"."ID" > 1;

\echo ''
\echo '=== 2. Documents sans affaire, mais leur source (table TR_*) en a une ==='

\echo '-- SAISIE_ACHAT <- COMMANDE'
select 'SAISIE_ACHAT <- COMMANDE (via TR_COMMANDE)' as cas, count(*) as documents
  from "OpenConcerto42"."SAISIE_ACHAT"
  join "OpenConcerto42"."TR_COMMANDE" on "OpenConcerto42"."TR_COMMANDE"."ID_SAISIE_ACHAT" = "OpenConcerto42"."SAISIE_ACHAT"."ID"
  join "OpenConcerto42"."COMMANDE" on "OpenConcerto42"."COMMANDE"."ID" = "OpenConcerto42"."TR_COMMANDE"."ID_COMMANDE"
 where ("OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" > 1
   and "OpenConcerto42"."TR_COMMANDE"."ID_SAISIE_ACHAT" > 1 and "OpenConcerto42"."TR_COMMANDE"."ID_COMMANDE" > 1
   and "OpenConcerto42"."SAISIE_ACHAT"."ID" > 1 and "OpenConcerto42"."COMMANDE"."ID" > 1;

\echo '-- BON_RECEPTION <- COMMANDE'
select 'BON_RECEPTION <- COMMANDE (via TR_COMMANDE)' as cas, count(*) as documents
  from "OpenConcerto42"."BON_RECEPTION"
  join "OpenConcerto42"."TR_COMMANDE" on "OpenConcerto42"."TR_COMMANDE"."ID_BON_RECEPTION" = "OpenConcerto42"."BON_RECEPTION"."ID"
  join "OpenConcerto42"."COMMANDE" on "OpenConcerto42"."COMMANDE"."ID" = "OpenConcerto42"."TR_COMMANDE"."ID_COMMANDE"
 where ("OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" > 1
   and "OpenConcerto42"."TR_COMMANDE"."ID_BON_RECEPTION" > 1 and "OpenConcerto42"."TR_COMMANDE"."ID_COMMANDE" > 1
   and "OpenConcerto42"."BON_RECEPTION"."ID" > 1 and "OpenConcerto42"."COMMANDE"."ID" > 1;

\echo '-- FACTURE_FOURNISSEUR <- COMMANDE'
select 'FACTURE_FOURNISSEUR <- COMMANDE (via TR_COMMANDE)' as cas, count(*) as documents
  from "OpenConcerto42"."FACTURE_FOURNISSEUR"
  join "OpenConcerto42"."TR_COMMANDE" on "OpenConcerto42"."TR_COMMANDE"."ID_FACTURE_FOURNISSEUR" = "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID"
  join "OpenConcerto42"."COMMANDE" on "OpenConcerto42"."COMMANDE"."ID" = "OpenConcerto42"."TR_COMMANDE"."ID_COMMANDE"
 where ("OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" > 1
   and "OpenConcerto42"."TR_COMMANDE"."ID_FACTURE_FOURNISSEUR" > 1 and "OpenConcerto42"."TR_COMMANDE"."ID_COMMANDE" > 1
   and "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID" > 1 and "OpenConcerto42"."COMMANDE"."ID" > 1;

\echo '-- SAISIE_ACHAT <- BON_RECEPTION'
select 'SAISIE_ACHAT <- BON_RECEPTION (via TR_BON_RECEPTION)' as cas, count(*) as documents
  from "OpenConcerto42"."SAISIE_ACHAT"
  join "OpenConcerto42"."TR_BON_RECEPTION" on "OpenConcerto42"."TR_BON_RECEPTION"."ID_SAISIE_ACHAT" = "OpenConcerto42"."SAISIE_ACHAT"."ID"
  join "OpenConcerto42"."BON_RECEPTION" on "OpenConcerto42"."BON_RECEPTION"."ID" = "OpenConcerto42"."TR_BON_RECEPTION"."ID_BON_RECEPTION"
 where ("OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" > 1
   and "OpenConcerto42"."TR_BON_RECEPTION"."ID_SAISIE_ACHAT" > 1 and "OpenConcerto42"."TR_BON_RECEPTION"."ID_BON_RECEPTION" > 1
   and "OpenConcerto42"."SAISIE_ACHAT"."ID" > 1 and "OpenConcerto42"."BON_RECEPTION"."ID" > 1;

\echo '-- FACTURE_FOURNISSEUR <- BON_RECEPTION'
select 'FACTURE_FOURNISSEUR <- BON_RECEPTION (via TR_BON_RECEPTION)' as cas, count(*) as documents
  from "OpenConcerto42"."FACTURE_FOURNISSEUR"
  join "OpenConcerto42"."TR_BON_RECEPTION" on "OpenConcerto42"."TR_BON_RECEPTION"."ID_FACTURE_FOURNISSEUR" = "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID"
  join "OpenConcerto42"."BON_RECEPTION" on "OpenConcerto42"."BON_RECEPTION"."ID" = "OpenConcerto42"."TR_BON_RECEPTION"."ID_BON_RECEPTION"
 where ("OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" > 1
   and "OpenConcerto42"."TR_BON_RECEPTION"."ID_FACTURE_FOURNISSEUR" > 1 and "OpenConcerto42"."TR_BON_RECEPTION"."ID_BON_RECEPTION" > 1
   and "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID" > 1 and "OpenConcerto42"."BON_RECEPTION"."ID" > 1;

\echo '-- COMMANDE <- DEVIS'
select 'COMMANDE <- DEVIS (via TR_DEVIS)' as cas, count(*) as documents
  from "OpenConcerto42"."COMMANDE"
  join "OpenConcerto42"."TR_DEVIS" on "OpenConcerto42"."TR_DEVIS"."ID_COMMANDE" = "OpenConcerto42"."COMMANDE"."ID"
  join "OpenConcerto42"."DEVIS" on "OpenConcerto42"."DEVIS"."ID_DEVIS" = "OpenConcerto42"."TR_DEVIS"."ID_DEVIS"
 where ("OpenConcerto42"."COMMANDE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."DEVIS"."ID_AFFAIRE" > 1
   and "OpenConcerto42"."TR_DEVIS"."ID_COMMANDE" > 1 and "OpenConcerto42"."TR_DEVIS"."ID_DEVIS" > 1
   and "OpenConcerto42"."COMMANDE"."ID" > 1 and "OpenConcerto42"."DEVIS"."ID_DEVIS" > 1;

\echo '-- AVOIR_FOURNISSEUR <- SAISIE_ACHAT'
select 'AVOIR_FOURNISSEUR <- SAISIE_ACHAT (via TR_SAISIE_ACHAT)' as cas, count(*) as documents
  from "OpenConcerto42"."AVOIR_FOURNISSEUR"
  join "OpenConcerto42"."TR_SAISIE_ACHAT" on "OpenConcerto42"."TR_SAISIE_ACHAT"."ID_AVOIR_FOURNISSEUR" = "OpenConcerto42"."AVOIR_FOURNISSEUR"."ID"
  join "OpenConcerto42"."SAISIE_ACHAT" on "OpenConcerto42"."SAISIE_ACHAT"."ID" = "OpenConcerto42"."TR_SAISIE_ACHAT"."ID_SAISIE_ACHAT"
 where ("OpenConcerto42"."AVOIR_FOURNISSEUR"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."AVOIR_FOURNISSEUR"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" > 1
   and "OpenConcerto42"."TR_SAISIE_ACHAT"."ID_AVOIR_FOURNISSEUR" > 1 and "OpenConcerto42"."TR_SAISIE_ACHAT"."ID_SAISIE_ACHAT" > 1
   and "OpenConcerto42"."AVOIR_FOURNISSEUR"."ID" > 1 and "OpenConcerto42"."SAISIE_ACHAT"."ID" > 1;

\echo '-- COMMANDE_CLIENT <- DEVIS'
select 'COMMANDE_CLIENT <- DEVIS (via TR_DEVIS)' as cas, count(*) as documents
  from "OpenConcerto42"."COMMANDE_CLIENT"
  join "OpenConcerto42"."TR_DEVIS" on "OpenConcerto42"."TR_DEVIS"."ID_COMMANDE_CLIENT" = "OpenConcerto42"."COMMANDE_CLIENT"."ID"
  join "OpenConcerto42"."DEVIS" on "OpenConcerto42"."DEVIS"."ID_DEVIS" = "OpenConcerto42"."TR_DEVIS"."ID_DEVIS"
 where ("OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."DEVIS"."ID_AFFAIRE" > 1
   and "OpenConcerto42"."TR_DEVIS"."ID_COMMANDE_CLIENT" > 1 and "OpenConcerto42"."TR_DEVIS"."ID_DEVIS" > 1
   and "OpenConcerto42"."COMMANDE_CLIENT"."ID" > 1 and "OpenConcerto42"."DEVIS"."ID_DEVIS" > 1;

\echo '-- SAISIE_VENTE_FACTURE <- DEVIS'
select 'SAISIE_VENTE_FACTURE <- DEVIS (via TR_DEVIS)' as cas, count(*) as documents
  from "OpenConcerto42"."SAISIE_VENTE_FACTURE"
  join "OpenConcerto42"."TR_DEVIS" on "OpenConcerto42"."TR_DEVIS"."ID_SAISIE_VENTE_FACTURE" = "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID"
  join "OpenConcerto42"."DEVIS" on "OpenConcerto42"."DEVIS"."ID_DEVIS" = "OpenConcerto42"."TR_DEVIS"."ID_DEVIS"
 where ("OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."DEVIS"."ID_AFFAIRE" > 1
   and "OpenConcerto42"."TR_DEVIS"."ID_SAISIE_VENTE_FACTURE" > 1 and "OpenConcerto42"."TR_DEVIS"."ID_DEVIS" > 1
   and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" > 1 and "OpenConcerto42"."DEVIS"."ID_DEVIS" > 1;

\echo '-- BON_DE_LIVRAISON <- DEVIS'
select 'BON_DE_LIVRAISON <- DEVIS (via TR_DEVIS)' as cas, count(*) as documents
  from "OpenConcerto42"."BON_DE_LIVRAISON"
  join "OpenConcerto42"."TR_DEVIS" on "OpenConcerto42"."TR_DEVIS"."ID_BON_DE_LIVRAISON" = "OpenConcerto42"."BON_DE_LIVRAISON"."ID"
  join "OpenConcerto42"."DEVIS" on "OpenConcerto42"."DEVIS"."ID_DEVIS" = "OpenConcerto42"."TR_DEVIS"."ID_DEVIS"
 where ("OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."DEVIS"."ID_AFFAIRE" > 1
   and "OpenConcerto42"."TR_DEVIS"."ID_BON_DE_LIVRAISON" > 1 and "OpenConcerto42"."TR_DEVIS"."ID_DEVIS" > 1
   and "OpenConcerto42"."BON_DE_LIVRAISON"."ID" > 1 and "OpenConcerto42"."DEVIS"."ID_DEVIS" > 1;

\echo '-- SAISIE_VENTE_FACTURE <- COMMANDE_CLIENT'
select 'SAISIE_VENTE_FACTURE <- COMMANDE_CLIENT (via TR_COMMANDE_CLIENT)' as cas, count(*) as documents
  from "OpenConcerto42"."SAISIE_VENTE_FACTURE"
  join "OpenConcerto42"."TR_COMMANDE_CLIENT" on "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_SAISIE_VENTE_FACTURE" = "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID"
  join "OpenConcerto42"."COMMANDE_CLIENT" on "OpenConcerto42"."COMMANDE_CLIENT"."ID" = "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE_CLIENT"
 where ("OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" > 1
   and "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_SAISIE_VENTE_FACTURE" > 1 and "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE_CLIENT" > 1
   and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" > 1 and "OpenConcerto42"."COMMANDE_CLIENT"."ID" > 1;

\echo '-- BON_DE_LIVRAISON <- COMMANDE_CLIENT'
select 'BON_DE_LIVRAISON <- COMMANDE_CLIENT (via TR_COMMANDE_CLIENT)' as cas, count(*) as documents
  from "OpenConcerto42"."BON_DE_LIVRAISON"
  join "OpenConcerto42"."TR_COMMANDE_CLIENT" on "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_BON_DE_LIVRAISON" = "OpenConcerto42"."BON_DE_LIVRAISON"."ID"
  join "OpenConcerto42"."COMMANDE_CLIENT" on "OpenConcerto42"."COMMANDE_CLIENT"."ID" = "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE_CLIENT"
 where ("OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" > 1
   and "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_BON_DE_LIVRAISON" > 1 and "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE_CLIENT" > 1
   and "OpenConcerto42"."BON_DE_LIVRAISON"."ID" > 1 and "OpenConcerto42"."COMMANDE_CLIENT"."ID" > 1;

\echo '-- COMMANDE <- COMMANDE_CLIENT'
select 'COMMANDE <- COMMANDE_CLIENT (via TR_COMMANDE_CLIENT)' as cas, count(*) as documents
  from "OpenConcerto42"."COMMANDE"
  join "OpenConcerto42"."TR_COMMANDE_CLIENT" on "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE" = "OpenConcerto42"."COMMANDE"."ID"
  join "OpenConcerto42"."COMMANDE_CLIENT" on "OpenConcerto42"."COMMANDE_CLIENT"."ID" = "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE_CLIENT"
 where ("OpenConcerto42"."COMMANDE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" > 1
   and "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE" > 1 and "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE_CLIENT" > 1
   and "OpenConcerto42"."COMMANDE"."ID" > 1 and "OpenConcerto42"."COMMANDE_CLIENT"."ID" > 1;

\echo '-- SAISIE_VENTE_FACTURE <- BON_DE_LIVRAISON'
select 'SAISIE_VENTE_FACTURE <- BON_DE_LIVRAISON (via TR_BON_DE_LIVRAISON)' as cas, count(*) as documents
  from "OpenConcerto42"."SAISIE_VENTE_FACTURE"
  join "OpenConcerto42"."TR_BON_DE_LIVRAISON" on "OpenConcerto42"."TR_BON_DE_LIVRAISON"."ID_SAISIE_VENTE_FACTURE" = "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID"
  join "OpenConcerto42"."BON_DE_LIVRAISON" on "OpenConcerto42"."BON_DE_LIVRAISON"."ID" = "OpenConcerto42"."TR_BON_DE_LIVRAISON"."ID_BON_DE_LIVRAISON"
 where ("OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" > 1
   and "OpenConcerto42"."TR_BON_DE_LIVRAISON"."ID_SAISIE_VENTE_FACTURE" > 1 and "OpenConcerto42"."TR_BON_DE_LIVRAISON"."ID_BON_DE_LIVRAISON" > 1
   and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" > 1 and "OpenConcerto42"."BON_DE_LIVRAISON"."ID" > 1;

\echo '-- AVOIR_CLIENT <- SAISIE_VENTE_FACTURE'
select 'AVOIR_CLIENT <- SAISIE_VENTE_FACTURE (via TR_SAISIE_VENTE_FACTURE)' as cas, count(*) as documents
  from "OpenConcerto42"."AVOIR_CLIENT"
  join "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE" on "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_AVOIR_CLIENT" = "OpenConcerto42"."AVOIR_CLIENT"."ID"
  join "OpenConcerto42"."SAISIE_VENTE_FACTURE" on "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" = "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_SAISIE_VENTE_FACTURE"
 where ("OpenConcerto42"."AVOIR_CLIENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."AVOIR_CLIENT"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" > 1
   and "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_AVOIR_CLIENT" > 1 and "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_SAISIE_VENTE_FACTURE" > 1
   and "OpenConcerto42"."AVOIR_CLIENT"."ID" > 1 and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" > 1;

\echo '-- BON_DE_LIVRAISON <- SAISIE_VENTE_FACTURE'
select 'BON_DE_LIVRAISON <- SAISIE_VENTE_FACTURE (via TR_SAISIE_VENTE_FACTURE)' as cas, count(*) as documents
  from "OpenConcerto42"."BON_DE_LIVRAISON"
  join "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE" on "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_BON_DE_LIVRAISON" = "OpenConcerto42"."BON_DE_LIVRAISON"."ID"
  join "OpenConcerto42"."SAISIE_VENTE_FACTURE" on "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" = "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_SAISIE_VENTE_FACTURE"
 where ("OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" > 1
   and "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_BON_DE_LIVRAISON" > 1 and "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_SAISIE_VENTE_FACTURE" > 1
   and "OpenConcerto42"."BON_DE_LIVRAISON"."ID" > 1 and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" > 1;

\echo '-- COMMANDE <- SAISIE_VENTE_FACTURE'
select 'COMMANDE <- SAISIE_VENTE_FACTURE (via TR_SAISIE_VENTE_FACTURE)' as cas, count(*) as documents
  from "OpenConcerto42"."COMMANDE"
  join "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE" on "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_COMMANDE" = "OpenConcerto42"."COMMANDE"."ID"
  join "OpenConcerto42"."SAISIE_VENTE_FACTURE" on "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" = "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_SAISIE_VENTE_FACTURE"
 where ("OpenConcerto42"."COMMANDE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" > 1
   and "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_COMMANDE" > 1 and "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_SAISIE_VENTE_FACTURE" > 1
   and "OpenConcerto42"."COMMANDE"."ID" > 1 and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" > 1;


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

select 'AVOIR_CLIENT' as document, count(*) as sans_affaire from "OpenConcerto42"."AVOIR_CLIENT" where ("OpenConcerto42"."AVOIR_CLIENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."AVOIR_CLIENT"."ID_AFFAIRE" = 1) and "OpenConcerto42"."AVOIR_CLIENT"."ID" > 1;
select 'AVOIR_FOURNISSEUR' as document, count(*) as sans_affaire from "OpenConcerto42"."AVOIR_FOURNISSEUR" where ("OpenConcerto42"."AVOIR_FOURNISSEUR"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."AVOIR_FOURNISSEUR"."ID_AFFAIRE" = 1) and "OpenConcerto42"."AVOIR_FOURNISSEUR"."ID" > 1;
select 'BON_DE_LIVRAISON' as document, count(*) as sans_affaire from "OpenConcerto42"."BON_DE_LIVRAISON" where ("OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" = 1) and "OpenConcerto42"."BON_DE_LIVRAISON"."ID" > 1;
select 'BON_RECEPTION' as document, count(*) as sans_affaire from "OpenConcerto42"."BON_RECEPTION" where ("OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" = 1) and "OpenConcerto42"."BON_RECEPTION"."ID" > 1;
select 'COMMANDE' as document, count(*) as sans_affaire from "OpenConcerto42"."COMMANDE" where ("OpenConcerto42"."COMMANDE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" = 1) and "OpenConcerto42"."COMMANDE"."ID" > 1;
select 'COMMANDE_CLIENT' as document, count(*) as sans_affaire from "OpenConcerto42"."COMMANDE_CLIENT" where ("OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" = 1) and "OpenConcerto42"."COMMANDE_CLIENT"."ID" > 1;
select 'DEVIS' as document, count(*) as sans_affaire from "OpenConcerto42"."DEVIS" where ("OpenConcerto42"."DEVIS"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."DEVIS"."ID_AFFAIRE" = 1) and "OpenConcerto42"."DEVIS"."ID_DEVIS" > 1;
select 'FACTURE_FOURNISSEUR' as document, count(*) as sans_affaire from "OpenConcerto42"."FACTURE_FOURNISSEUR" where ("OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" = 1) and "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID" > 1;
select 'SAISIE_ACHAT' as document, count(*) as sans_affaire from "OpenConcerto42"."SAISIE_ACHAT" where ("OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" = 1) and "OpenConcerto42"."SAISIE_ACHAT"."ID" > 1;
select 'SAISIE_VENTE_FACTURE' as document, count(*) as sans_affaire from "OpenConcerto42"."SAISIE_VENTE_FACTURE" where ("OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" = 1) and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" > 1;

\echo '################################################################'
\echo '# 2. Verdict : le nombre que le menu doit annoncer'
\echo '################################################################'

select sum(documents) as total_a_reprendre from (
  select count(*) as documents from "OpenConcerto42"."SAISIE_ACHAT"
    join "OpenConcerto42"."COMMANDE" on "OpenConcerto42"."COMMANDE"."ID" = "OpenConcerto42"."SAISIE_ACHAT"."IDSOURCE"
   where "OpenConcerto42"."SAISIE_ACHAT"."SOURCE" = 'COMMANDE' and ("OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" = 1) and "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."SAISIE_ACHAT"."ID" > 1 and "OpenConcerto42"."COMMANDE"."ID" > 1 and "OpenConcerto42"."SAISIE_ACHAT"."IDSOURCE" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."SAISIE_ACHAT"
    join "OpenConcerto42"."BON_RECEPTION" on "OpenConcerto42"."BON_RECEPTION"."ID" = "OpenConcerto42"."SAISIE_ACHAT"."IDSOURCE"
   where "OpenConcerto42"."SAISIE_ACHAT"."SOURCE" = 'BON_RECEPTION' and ("OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" = 1) and "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."SAISIE_ACHAT"."ID" > 1 and "OpenConcerto42"."BON_RECEPTION"."ID" > 1 and "OpenConcerto42"."SAISIE_ACHAT"."IDSOURCE" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."SAISIE_ACHAT"
    join "OpenConcerto42"."TR_COMMANDE" on "OpenConcerto42"."TR_COMMANDE"."ID_SAISIE_ACHAT" = "OpenConcerto42"."SAISIE_ACHAT"."ID"
    join "OpenConcerto42"."COMMANDE" on "OpenConcerto42"."COMMANDE"."ID" = "OpenConcerto42"."TR_COMMANDE"."ID_COMMANDE"
   where ("OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" = 1) and "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."TR_COMMANDE"."ID_SAISIE_ACHAT" > 1 and "OpenConcerto42"."TR_COMMANDE"."ID_COMMANDE" > 1
     and "OpenConcerto42"."SAISIE_ACHAT"."ID" > 1 and "OpenConcerto42"."COMMANDE"."ID" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."BON_RECEPTION"
    join "OpenConcerto42"."TR_COMMANDE" on "OpenConcerto42"."TR_COMMANDE"."ID_BON_RECEPTION" = "OpenConcerto42"."BON_RECEPTION"."ID"
    join "OpenConcerto42"."COMMANDE" on "OpenConcerto42"."COMMANDE"."ID" = "OpenConcerto42"."TR_COMMANDE"."ID_COMMANDE"
   where ("OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" = 1) and "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."TR_COMMANDE"."ID_BON_RECEPTION" > 1 and "OpenConcerto42"."TR_COMMANDE"."ID_COMMANDE" > 1
     and "OpenConcerto42"."BON_RECEPTION"."ID" > 1 and "OpenConcerto42"."COMMANDE"."ID" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."FACTURE_FOURNISSEUR"
    join "OpenConcerto42"."TR_COMMANDE" on "OpenConcerto42"."TR_COMMANDE"."ID_FACTURE_FOURNISSEUR" = "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID"
    join "OpenConcerto42"."COMMANDE" on "OpenConcerto42"."COMMANDE"."ID" = "OpenConcerto42"."TR_COMMANDE"."ID_COMMANDE"
   where ("OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" = 1) and "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."TR_COMMANDE"."ID_FACTURE_FOURNISSEUR" > 1 and "OpenConcerto42"."TR_COMMANDE"."ID_COMMANDE" > 1
     and "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID" > 1 and "OpenConcerto42"."COMMANDE"."ID" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."SAISIE_ACHAT"
    join "OpenConcerto42"."TR_BON_RECEPTION" on "OpenConcerto42"."TR_BON_RECEPTION"."ID_SAISIE_ACHAT" = "OpenConcerto42"."SAISIE_ACHAT"."ID"
    join "OpenConcerto42"."BON_RECEPTION" on "OpenConcerto42"."BON_RECEPTION"."ID" = "OpenConcerto42"."TR_BON_RECEPTION"."ID_BON_RECEPTION"
   where ("OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" = 1) and "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."TR_BON_RECEPTION"."ID_SAISIE_ACHAT" > 1 and "OpenConcerto42"."TR_BON_RECEPTION"."ID_BON_RECEPTION" > 1
     and "OpenConcerto42"."SAISIE_ACHAT"."ID" > 1 and "OpenConcerto42"."BON_RECEPTION"."ID" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."FACTURE_FOURNISSEUR"
    join "OpenConcerto42"."TR_BON_RECEPTION" on "OpenConcerto42"."TR_BON_RECEPTION"."ID_FACTURE_FOURNISSEUR" = "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID"
    join "OpenConcerto42"."BON_RECEPTION" on "OpenConcerto42"."BON_RECEPTION"."ID" = "OpenConcerto42"."TR_BON_RECEPTION"."ID_BON_RECEPTION"
   where ("OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" = 1) and "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."TR_BON_RECEPTION"."ID_FACTURE_FOURNISSEUR" > 1 and "OpenConcerto42"."TR_BON_RECEPTION"."ID_BON_RECEPTION" > 1
     and "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID" > 1 and "OpenConcerto42"."BON_RECEPTION"."ID" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."COMMANDE"
    join "OpenConcerto42"."TR_DEVIS" on "OpenConcerto42"."TR_DEVIS"."ID_COMMANDE" = "OpenConcerto42"."COMMANDE"."ID"
    join "OpenConcerto42"."DEVIS" on "OpenConcerto42"."DEVIS"."ID_DEVIS" = "OpenConcerto42"."TR_DEVIS"."ID_DEVIS"
   where ("OpenConcerto42"."COMMANDE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" = 1) and "OpenConcerto42"."DEVIS"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."TR_DEVIS"."ID_COMMANDE" > 1 and "OpenConcerto42"."TR_DEVIS"."ID_DEVIS" > 1
     and "OpenConcerto42"."COMMANDE"."ID" > 1 and "OpenConcerto42"."DEVIS"."ID_DEVIS" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."AVOIR_FOURNISSEUR"
    join "OpenConcerto42"."TR_SAISIE_ACHAT" on "OpenConcerto42"."TR_SAISIE_ACHAT"."ID_AVOIR_FOURNISSEUR" = "OpenConcerto42"."AVOIR_FOURNISSEUR"."ID"
    join "OpenConcerto42"."SAISIE_ACHAT" on "OpenConcerto42"."SAISIE_ACHAT"."ID" = "OpenConcerto42"."TR_SAISIE_ACHAT"."ID_SAISIE_ACHAT"
   where ("OpenConcerto42"."AVOIR_FOURNISSEUR"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."AVOIR_FOURNISSEUR"."ID_AFFAIRE" = 1) and "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."TR_SAISIE_ACHAT"."ID_AVOIR_FOURNISSEUR" > 1 and "OpenConcerto42"."TR_SAISIE_ACHAT"."ID_SAISIE_ACHAT" > 1
     and "OpenConcerto42"."AVOIR_FOURNISSEUR"."ID" > 1 and "OpenConcerto42"."SAISIE_ACHAT"."ID" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."COMMANDE_CLIENT"
    join "OpenConcerto42"."TR_DEVIS" on "OpenConcerto42"."TR_DEVIS"."ID_COMMANDE_CLIENT" = "OpenConcerto42"."COMMANDE_CLIENT"."ID"
    join "OpenConcerto42"."DEVIS" on "OpenConcerto42"."DEVIS"."ID_DEVIS" = "OpenConcerto42"."TR_DEVIS"."ID_DEVIS"
   where ("OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" = 1) and "OpenConcerto42"."DEVIS"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."TR_DEVIS"."ID_COMMANDE_CLIENT" > 1 and "OpenConcerto42"."TR_DEVIS"."ID_DEVIS" > 1
     and "OpenConcerto42"."COMMANDE_CLIENT"."ID" > 1 and "OpenConcerto42"."DEVIS"."ID_DEVIS" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."SAISIE_VENTE_FACTURE"
    join "OpenConcerto42"."TR_DEVIS" on "OpenConcerto42"."TR_DEVIS"."ID_SAISIE_VENTE_FACTURE" = "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID"
    join "OpenConcerto42"."DEVIS" on "OpenConcerto42"."DEVIS"."ID_DEVIS" = "OpenConcerto42"."TR_DEVIS"."ID_DEVIS"
   where ("OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" = 1) and "OpenConcerto42"."DEVIS"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."TR_DEVIS"."ID_SAISIE_VENTE_FACTURE" > 1 and "OpenConcerto42"."TR_DEVIS"."ID_DEVIS" > 1
     and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" > 1 and "OpenConcerto42"."DEVIS"."ID_DEVIS" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."BON_DE_LIVRAISON"
    join "OpenConcerto42"."TR_DEVIS" on "OpenConcerto42"."TR_DEVIS"."ID_BON_DE_LIVRAISON" = "OpenConcerto42"."BON_DE_LIVRAISON"."ID"
    join "OpenConcerto42"."DEVIS" on "OpenConcerto42"."DEVIS"."ID_DEVIS" = "OpenConcerto42"."TR_DEVIS"."ID_DEVIS"
   where ("OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" = 1) and "OpenConcerto42"."DEVIS"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."TR_DEVIS"."ID_BON_DE_LIVRAISON" > 1 and "OpenConcerto42"."TR_DEVIS"."ID_DEVIS" > 1
     and "OpenConcerto42"."BON_DE_LIVRAISON"."ID" > 1 and "OpenConcerto42"."DEVIS"."ID_DEVIS" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."SAISIE_VENTE_FACTURE"
    join "OpenConcerto42"."TR_COMMANDE_CLIENT" on "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_SAISIE_VENTE_FACTURE" = "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID"
    join "OpenConcerto42"."COMMANDE_CLIENT" on "OpenConcerto42"."COMMANDE_CLIENT"."ID" = "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE_CLIENT"
   where ("OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" = 1) and "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_SAISIE_VENTE_FACTURE" > 1 and "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE_CLIENT" > 1
     and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" > 1 and "OpenConcerto42"."COMMANDE_CLIENT"."ID" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."BON_DE_LIVRAISON"
    join "OpenConcerto42"."TR_COMMANDE_CLIENT" on "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_BON_DE_LIVRAISON" = "OpenConcerto42"."BON_DE_LIVRAISON"."ID"
    join "OpenConcerto42"."COMMANDE_CLIENT" on "OpenConcerto42"."COMMANDE_CLIENT"."ID" = "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE_CLIENT"
   where ("OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" = 1) and "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_BON_DE_LIVRAISON" > 1 and "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE_CLIENT" > 1
     and "OpenConcerto42"."BON_DE_LIVRAISON"."ID" > 1 and "OpenConcerto42"."COMMANDE_CLIENT"."ID" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."COMMANDE"
    join "OpenConcerto42"."TR_COMMANDE_CLIENT" on "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE" = "OpenConcerto42"."COMMANDE"."ID"
    join "OpenConcerto42"."COMMANDE_CLIENT" on "OpenConcerto42"."COMMANDE_CLIENT"."ID" = "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE_CLIENT"
   where ("OpenConcerto42"."COMMANDE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" = 1) and "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE" > 1 and "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE_CLIENT" > 1
     and "OpenConcerto42"."COMMANDE"."ID" > 1 and "OpenConcerto42"."COMMANDE_CLIENT"."ID" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."SAISIE_VENTE_FACTURE"
    join "OpenConcerto42"."TR_BON_DE_LIVRAISON" on "OpenConcerto42"."TR_BON_DE_LIVRAISON"."ID_SAISIE_VENTE_FACTURE" = "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID"
    join "OpenConcerto42"."BON_DE_LIVRAISON" on "OpenConcerto42"."BON_DE_LIVRAISON"."ID" = "OpenConcerto42"."TR_BON_DE_LIVRAISON"."ID_BON_DE_LIVRAISON"
   where ("OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" = 1) and "OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."TR_BON_DE_LIVRAISON"."ID_SAISIE_VENTE_FACTURE" > 1 and "OpenConcerto42"."TR_BON_DE_LIVRAISON"."ID_BON_DE_LIVRAISON" > 1
     and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" > 1 and "OpenConcerto42"."BON_DE_LIVRAISON"."ID" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."AVOIR_CLIENT"
    join "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE" on "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_AVOIR_CLIENT" = "OpenConcerto42"."AVOIR_CLIENT"."ID"
    join "OpenConcerto42"."SAISIE_VENTE_FACTURE" on "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" = "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_SAISIE_VENTE_FACTURE"
   where ("OpenConcerto42"."AVOIR_CLIENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."AVOIR_CLIENT"."ID_AFFAIRE" = 1) and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_AVOIR_CLIENT" > 1 and "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_SAISIE_VENTE_FACTURE" > 1
     and "OpenConcerto42"."AVOIR_CLIENT"."ID" > 1 and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."BON_DE_LIVRAISON"
    join "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE" on "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_BON_DE_LIVRAISON" = "OpenConcerto42"."BON_DE_LIVRAISON"."ID"
    join "OpenConcerto42"."SAISIE_VENTE_FACTURE" on "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" = "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_SAISIE_VENTE_FACTURE"
   where ("OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" = 1) and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_BON_DE_LIVRAISON" > 1 and "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_SAISIE_VENTE_FACTURE" > 1
     and "OpenConcerto42"."BON_DE_LIVRAISON"."ID" > 1 and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."COMMANDE"
    join "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE" on "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_COMMANDE" = "OpenConcerto42"."COMMANDE"."ID"
    join "OpenConcerto42"."SAISIE_VENTE_FACTURE" on "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" = "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_SAISIE_VENTE_FACTURE"
   where ("OpenConcerto42"."COMMANDE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" = 1) and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_COMMANDE" > 1 and "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_SAISIE_VENTE_FACTURE" > 1
     and "OpenConcerto42"."COMMANDE"."ID" > 1 and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" > 1
) x;

\echo '################################################################'
\echo '# 3. Garde-fou « Indefini » : la ligne 1 n est jamais un document'
\echo '################################################################'
--
-- Ces compteurs ne sont PAS des erreurs : la ligne 1 existe dans chaque table.
-- Ils servent a verifier qu'elle n'est jamais prise pour un document.

\echo '--- 3.x TR_COMMANDE : lignes pointant la ligne 1 (normal, non comptees) ---'
select count(*) filter (where "OpenConcerto42"."TR_COMMANDE"."ID_SAISIE_ACHAT" = 1) as vers_indefini_cible,
       count(*) filter (where "OpenConcerto42"."TR_COMMANDE"."ID_COMMANDE" = 1) as vers_indefini_source,
       count(*) as lignes_total
  from "OpenConcerto42"."TR_COMMANDE";

\echo '--- 3.x TR_COMMANDE : lignes pointant la ligne 1 (normal, non comptees) ---'
select count(*) filter (where "OpenConcerto42"."TR_COMMANDE"."ID_BON_RECEPTION" = 1) as vers_indefini_cible,
       count(*) filter (where "OpenConcerto42"."TR_COMMANDE"."ID_COMMANDE" = 1) as vers_indefini_source,
       count(*) as lignes_total
  from "OpenConcerto42"."TR_COMMANDE";

\echo '--- 3.x TR_COMMANDE : lignes pointant la ligne 1 (normal, non comptees) ---'
select count(*) filter (where "OpenConcerto42"."TR_COMMANDE"."ID_FACTURE_FOURNISSEUR" = 1) as vers_indefini_cible,
       count(*) filter (where "OpenConcerto42"."TR_COMMANDE"."ID_COMMANDE" = 1) as vers_indefini_source,
       count(*) as lignes_total
  from "OpenConcerto42"."TR_COMMANDE";

\echo '--- 3.x TR_BON_RECEPTION : lignes pointant la ligne 1 (normal, non comptees) ---'
select count(*) filter (where "OpenConcerto42"."TR_BON_RECEPTION"."ID_SAISIE_ACHAT" = 1) as vers_indefini_cible,
       count(*) filter (where "OpenConcerto42"."TR_BON_RECEPTION"."ID_BON_RECEPTION" = 1) as vers_indefini_source,
       count(*) as lignes_total
  from "OpenConcerto42"."TR_BON_RECEPTION";

\echo '--- 3.x TR_BON_RECEPTION : lignes pointant la ligne 1 (normal, non comptees) ---'
select count(*) filter (where "OpenConcerto42"."TR_BON_RECEPTION"."ID_FACTURE_FOURNISSEUR" = 1) as vers_indefini_cible,
       count(*) filter (where "OpenConcerto42"."TR_BON_RECEPTION"."ID_BON_RECEPTION" = 1) as vers_indefini_source,
       count(*) as lignes_total
  from "OpenConcerto42"."TR_BON_RECEPTION";

\echo '--- 3.x TR_DEVIS : lignes pointant la ligne 1 (normal, non comptees) ---'
select count(*) filter (where "OpenConcerto42"."TR_DEVIS"."ID_COMMANDE" = 1) as vers_indefini_cible,
       count(*) filter (where "OpenConcerto42"."TR_DEVIS"."ID_DEVIS" = 1) as vers_indefini_source,
       count(*) as lignes_total
  from "OpenConcerto42"."TR_DEVIS";

\echo '--- 3.x TR_SAISIE_ACHAT : lignes pointant la ligne 1 (normal, non comptees) ---'
select count(*) filter (where "OpenConcerto42"."TR_SAISIE_ACHAT"."ID_AVOIR_FOURNISSEUR" = 1) as vers_indefini_cible,
       count(*) filter (where "OpenConcerto42"."TR_SAISIE_ACHAT"."ID_SAISIE_ACHAT" = 1) as vers_indefini_source,
       count(*) as lignes_total
  from "OpenConcerto42"."TR_SAISIE_ACHAT";

\echo '--- 3.x TR_DEVIS : lignes pointant la ligne 1 (normal, non comptees) ---'
select count(*) filter (where "OpenConcerto42"."TR_DEVIS"."ID_COMMANDE_CLIENT" = 1) as vers_indefini_cible,
       count(*) filter (where "OpenConcerto42"."TR_DEVIS"."ID_DEVIS" = 1) as vers_indefini_source,
       count(*) as lignes_total
  from "OpenConcerto42"."TR_DEVIS";

\echo '--- 3.x TR_DEVIS : lignes pointant la ligne 1 (normal, non comptees) ---'
select count(*) filter (where "OpenConcerto42"."TR_DEVIS"."ID_SAISIE_VENTE_FACTURE" = 1) as vers_indefini_cible,
       count(*) filter (where "OpenConcerto42"."TR_DEVIS"."ID_DEVIS" = 1) as vers_indefini_source,
       count(*) as lignes_total
  from "OpenConcerto42"."TR_DEVIS";

\echo '--- 3.x TR_DEVIS : lignes pointant la ligne 1 (normal, non comptees) ---'
select count(*) filter (where "OpenConcerto42"."TR_DEVIS"."ID_BON_DE_LIVRAISON" = 1) as vers_indefini_cible,
       count(*) filter (where "OpenConcerto42"."TR_DEVIS"."ID_DEVIS" = 1) as vers_indefini_source,
       count(*) as lignes_total
  from "OpenConcerto42"."TR_DEVIS";

\echo '--- 3.x TR_COMMANDE_CLIENT : lignes pointant la ligne 1 (normal, non comptees) ---'
select count(*) filter (where "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_SAISIE_VENTE_FACTURE" = 1) as vers_indefini_cible,
       count(*) filter (where "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE_CLIENT" = 1) as vers_indefini_source,
       count(*) as lignes_total
  from "OpenConcerto42"."TR_COMMANDE_CLIENT";

\echo '--- 3.x TR_COMMANDE_CLIENT : lignes pointant la ligne 1 (normal, non comptees) ---'
select count(*) filter (where "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_BON_DE_LIVRAISON" = 1) as vers_indefini_cible,
       count(*) filter (where "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE_CLIENT" = 1) as vers_indefini_source,
       count(*) as lignes_total
  from "OpenConcerto42"."TR_COMMANDE_CLIENT";

\echo '--- 3.x TR_COMMANDE_CLIENT : lignes pointant la ligne 1 (normal, non comptees) ---'
select count(*) filter (where "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE" = 1) as vers_indefini_cible,
       count(*) filter (where "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE_CLIENT" = 1) as vers_indefini_source,
       count(*) as lignes_total
  from "OpenConcerto42"."TR_COMMANDE_CLIENT";

\echo '--- 3.x TR_BON_DE_LIVRAISON : lignes pointant la ligne 1 (normal, non comptees) ---'
select count(*) filter (where "OpenConcerto42"."TR_BON_DE_LIVRAISON"."ID_SAISIE_VENTE_FACTURE" = 1) as vers_indefini_cible,
       count(*) filter (where "OpenConcerto42"."TR_BON_DE_LIVRAISON"."ID_BON_DE_LIVRAISON" = 1) as vers_indefini_source,
       count(*) as lignes_total
  from "OpenConcerto42"."TR_BON_DE_LIVRAISON";

\echo '--- 3.x TR_SAISIE_VENTE_FACTURE : lignes pointant la ligne 1 (normal, non comptees) ---'
select count(*) filter (where "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_AVOIR_CLIENT" = 1) as vers_indefini_cible,
       count(*) filter (where "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_SAISIE_VENTE_FACTURE" = 1) as vers_indefini_source,
       count(*) as lignes_total
  from "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE";

\echo '--- 3.x TR_SAISIE_VENTE_FACTURE : lignes pointant la ligne 1 (normal, non comptees) ---'
select count(*) filter (where "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_BON_DE_LIVRAISON" = 1) as vers_indefini_cible,
       count(*) filter (where "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_SAISIE_VENTE_FACTURE" = 1) as vers_indefini_source,
       count(*) as lignes_total
  from "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE";

\echo '--- 3.x TR_SAISIE_VENTE_FACTURE : lignes pointant la ligne 1 (normal, non comptees) ---'
select count(*) filter (where "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_COMMANDE" = 1) as vers_indefini_cible,
       count(*) filter (where "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_SAISIE_VENTE_FACTURE" = 1) as vers_indefini_source,
       count(*) as lignes_total
  from "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE";

\echo '--- 3.99 Documents dont l affaire vaut 1 : ils n ont pas de document d origine ---'
select 'AVOIR_CLIENT' as tableau, count(*) as affaire_indefinie from "OpenConcerto42"."AVOIR_CLIENT" where "OpenConcerto42"."AVOIR_CLIENT"."ID_AFFAIRE" = 1 and "OpenConcerto42"."AVOIR_CLIENT"."ID" > 1;
select 'AVOIR_FOURNISSEUR' as tableau, count(*) as affaire_indefinie from "OpenConcerto42"."AVOIR_FOURNISSEUR" where "OpenConcerto42"."AVOIR_FOURNISSEUR"."ID_AFFAIRE" = 1 and "OpenConcerto42"."AVOIR_FOURNISSEUR"."ID" > 1;
select 'BON_DE_LIVRAISON' as tableau, count(*) as affaire_indefinie from "OpenConcerto42"."BON_DE_LIVRAISON" where "OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" = 1 and "OpenConcerto42"."BON_DE_LIVRAISON"."ID" > 1;
select 'BON_RECEPTION' as tableau, count(*) as affaire_indefinie from "OpenConcerto42"."BON_RECEPTION" where "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" = 1 and "OpenConcerto42"."BON_RECEPTION"."ID" > 1;
select 'COMMANDE' as tableau, count(*) as affaire_indefinie from "OpenConcerto42"."COMMANDE" where "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" = 1 and "OpenConcerto42"."COMMANDE"."ID" > 1;
select 'COMMANDE_CLIENT' as tableau, count(*) as affaire_indefinie from "OpenConcerto42"."COMMANDE_CLIENT" where "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" = 1 and "OpenConcerto42"."COMMANDE_CLIENT"."ID" > 1;
select 'DEVIS' as tableau, count(*) as affaire_indefinie from "OpenConcerto42"."DEVIS" where "OpenConcerto42"."DEVIS"."ID_AFFAIRE" = 1 and "OpenConcerto42"."DEVIS"."ID_DEVIS" > 1;
select 'FACTURE_FOURNISSEUR' as tableau, count(*) as affaire_indefinie from "OpenConcerto42"."FACTURE_FOURNISSEUR" where "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" = 1 and "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID" > 1;
select 'SAISIE_ACHAT' as tableau, count(*) as affaire_indefinie from "OpenConcerto42"."SAISIE_ACHAT" where "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" = 1 and "OpenConcerto42"."SAISIE_ACHAT"."ID" > 1;
select 'SAISIE_VENTE_FACTURE' as tableau, count(*) as affaire_indefinie from "OpenConcerto42"."SAISIE_VENTE_FACTURE" where "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" = 1 and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" > 1;

\echo '################################################################'
\echo '# 4. Tableaux de lignes (attendu : 0)'
\echo '################################################################'

\echo '=== 0. Tableaux de lignes qui portent la colonne ID_AFFAIRE ==='
\echo '(seuls ceux qui sont listes ; pour les autres, l erreur'
\echo ' « column ... does not exist » est la reponse attendue, pas un incident)'
select table_name
  from information_schema.columns
 where table_schema = 'OpenConcerto42' and column_name = 'ID_AFFAIRE'
   and table_name like '%_ELEMENT'
 order by 1;

\echo ''
\echo '=== 1. Lignes sans affaire, alors que leur document en a une ==='

select 'COMMANDE_ELEMENT' as table_lignes, count(*) as lignes
  from "OpenConcerto42"."COMMANDE_ELEMENT"
  join "OpenConcerto42"."COMMANDE" on "OpenConcerto42"."COMMANDE"."ID" = "OpenConcerto42"."COMMANDE_ELEMENT"."ID_COMMANDE"
 where ("OpenConcerto42"."COMMANDE_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE_ELEMENT"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" > 1 union all
select 'FACTURE_FOURNISSEUR_ELEMENT' as table_lignes, count(*) as lignes
  from "OpenConcerto42"."FACTURE_FOURNISSEUR_ELEMENT"
  join "OpenConcerto42"."FACTURE_FOURNISSEUR" on "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID" = "OpenConcerto42"."FACTURE_FOURNISSEUR_ELEMENT"."ID_FACTURE_FOURNISSEUR"
 where ("OpenConcerto42"."FACTURE_FOURNISSEUR_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."FACTURE_FOURNISSEUR_ELEMENT"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" > 1 union all
select 'BON_RECEPTION_ELEMENT' as table_lignes, count(*) as lignes
  from "OpenConcerto42"."BON_RECEPTION_ELEMENT"
  join "OpenConcerto42"."BON_RECEPTION" on "OpenConcerto42"."BON_RECEPTION"."ID" = "OpenConcerto42"."BON_RECEPTION_ELEMENT"."ID_BON_RECEPTION"
 where ("OpenConcerto42"."BON_RECEPTION_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_RECEPTION_ELEMENT"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" > 1 union all
select 'DEMANDE_PRIX_ELEMENT' as table_lignes, count(*) as lignes
  from "OpenConcerto42"."DEMANDE_PRIX_ELEMENT"
  join "OpenConcerto42"."DEMANDE_PRIX" on "OpenConcerto42"."DEMANDE_PRIX"."ID" = "OpenConcerto42"."DEMANDE_PRIX_ELEMENT"."ID_DEMANDE_PRIX"
 where ("OpenConcerto42"."DEMANDE_PRIX_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."DEMANDE_PRIX_ELEMENT"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."DEMANDE_PRIX"."ID_AFFAIRE" > 1 union all
select 'DEMANDE_ACHAT_ELEMENT' as table_lignes, count(*) as lignes
  from "OpenConcerto42"."DEMANDE_ACHAT_ELEMENT"
  join "OpenConcerto42"."DEMANDE_ACHAT" on "OpenConcerto42"."DEMANDE_ACHAT"."ID" = "OpenConcerto42"."DEMANDE_ACHAT_ELEMENT"."ID_DEMANDE_ACHAT"
 where ("OpenConcerto42"."DEMANDE_ACHAT_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."DEMANDE_ACHAT_ELEMENT"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."DEMANDE_ACHAT"."ID_AFFAIRE" > 1 union all
select 'SAISIE_ACHAT_ELEMENT' as table_lignes, count(*) as lignes
  from "OpenConcerto42"."SAISIE_ACHAT_ELEMENT"
  join "OpenConcerto42"."SAISIE_ACHAT" on "OpenConcerto42"."SAISIE_ACHAT"."ID" = "OpenConcerto42"."SAISIE_ACHAT_ELEMENT"."ID_SAISIE_ACHAT"
 where ("OpenConcerto42"."SAISIE_ACHAT_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_ACHAT_ELEMENT"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" > 1 union all
select 'AVOIR_FOURNISSEUR_ELEMENT' as table_lignes, count(*) as lignes
  from "OpenConcerto42"."AVOIR_FOURNISSEUR_ELEMENT"
  join "OpenConcerto42"."AVOIR_FOURNISSEUR" on "OpenConcerto42"."AVOIR_FOURNISSEUR"."ID" = "OpenConcerto42"."AVOIR_FOURNISSEUR_ELEMENT"."ID_AVOIR_FOURNISSEUR"
 where ("OpenConcerto42"."AVOIR_FOURNISSEUR_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."AVOIR_FOURNISSEUR_ELEMENT"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."AVOIR_FOURNISSEUR"."ID_AFFAIRE" > 1 union all
select 'COMMANDE_CLIENT_ELEMENT' as table_lignes, count(*) as lignes
  from "OpenConcerto42"."COMMANDE_CLIENT_ELEMENT"
  join "OpenConcerto42"."COMMANDE_CLIENT" on "OpenConcerto42"."COMMANDE_CLIENT"."ID" = "OpenConcerto42"."COMMANDE_CLIENT_ELEMENT"."ID_COMMANDE_CLIENT"
 where ("OpenConcerto42"."COMMANDE_CLIENT_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE_CLIENT_ELEMENT"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" > 1 union all
select 'SAISIE_VENTE_FACTURE_ELEMENT' as table_lignes, count(*) as lignes
  from "OpenConcerto42"."SAISIE_VENTE_FACTURE_ELEMENT"
  join "OpenConcerto42"."SAISIE_VENTE_FACTURE" on "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" = "OpenConcerto42"."SAISIE_VENTE_FACTURE_ELEMENT"."ID_SAISIE_VENTE_FACTURE"
 where ("OpenConcerto42"."SAISIE_VENTE_FACTURE_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_VENTE_FACTURE_ELEMENT"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" > 1 union all
select 'DEVIS_ELEMENT' as table_lignes, count(*) as lignes
  from "OpenConcerto42"."DEVIS_ELEMENT"
  join "OpenConcerto42"."DEVIS" on "OpenConcerto42"."DEVIS"."ID_DEVIS" = "OpenConcerto42"."DEVIS_ELEMENT"."ID_DEVIS"
 where ("OpenConcerto42"."DEVIS_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."DEVIS_ELEMENT"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."DEVIS"."ID_AFFAIRE" > 1 union all
select 'AVOIR_CLIENT_ELEMENT' as table_lignes, count(*) as lignes
  from "OpenConcerto42"."AVOIR_CLIENT_ELEMENT"
  join "OpenConcerto42"."AVOIR_CLIENT" on "OpenConcerto42"."AVOIR_CLIENT"."ID" = "OpenConcerto42"."AVOIR_CLIENT_ELEMENT"."ID_AVOIR_CLIENT"
 where ("OpenConcerto42"."AVOIR_CLIENT_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."AVOIR_CLIENT_ELEMENT"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."AVOIR_CLIENT"."ID_AFFAIRE" > 1 union all
select 'BON_DE_LIVRAISON_ELEMENT' as table_lignes, count(*) as lignes
  from "OpenConcerto42"."BON_DE_LIVRAISON_ELEMENT"
  join "OpenConcerto42"."BON_DE_LIVRAISON" on "OpenConcerto42"."BON_DE_LIVRAISON"."ID" = "OpenConcerto42"."BON_DE_LIVRAISON_ELEMENT"."ID_BON_DE_LIVRAISON"
 where ("OpenConcerto42"."BON_DE_LIVRAISON_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_DE_LIVRAISON_ELEMENT"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" > 1;

\echo '################################################################'
\echo '# 5. Affaire temoin : controle visuel de « Historique affaires »'
\echo '################################################################'
--
-- Le numero ci-dessous est un EXEMPLE mesure sur la base du client : remplacez-le
-- par une affaire de votre choix. Si la fenetre affiche moins de lignes que la
-- section 5.2, la difference s'explique par ARCHIVE = 1 (OpenConcerto ne montre
-- pas les documents archives).
drop table if exists cible;
create temp table cible as select 12085 as numero;

\echo '--- 5.1 L affaire (son ID sert a toutes les jointures) ---'
select "ID" as id_affaire, "NUMERO" from "OpenConcerto42"."AFFAIRE" where "NUMERO" = (select cast(numero as text) from cible);

\echo '--- 5.2 Factures fournisseur : en base, archivees, affichables ---'
select count(*) as en_base,
       count(*) filter (where f."ARCHIVE" = 1) as archivees,
       count(*) filter (where f."ARCHIVE" = 0) as affichables
  from "OpenConcerto42"."FACTURE_FOURNISSEUR" f
 where f."ID_AFFAIRE" = (select "ID" from "OpenConcerto42"."AFFAIRE" a where a."NUMERO" = (select cast(numero as text) from cible));

\echo '--- 5.3 Leur numero, avec l etat d archive ---'
select f."NUMERO", f."DATE", f."ARCHIVE" as archive
  from "OpenConcerto42"."FACTURE_FOURNISSEUR" f
 where f."ID_AFFAIRE" = (select "ID" from "OpenConcerto42"."AFFAIRE" a where a."NUMERO" = (select cast(numero as text) from cible))
 order by f."NUMERO";


\echo '################################################################'
\echo '# 6. Verdict final'
\echo '################################################################'
--
-- Une seule ligne : 0 = tout est repris, sinon le nombre restant.
select sum(documents) as reste_a_reprendre from (
  select count(*) as documents from "OpenConcerto42"."SAISIE_ACHAT"
    join "OpenConcerto42"."COMMANDE" on "OpenConcerto42"."COMMANDE"."ID" = "OpenConcerto42"."SAISIE_ACHAT"."IDSOURCE"
   where "OpenConcerto42"."SAISIE_ACHAT"."SOURCE" = 'COMMANDE' and ("OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" = 1) and "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."SAISIE_ACHAT"."ID" > 1 and "OpenConcerto42"."COMMANDE"."ID" > 1 and "OpenConcerto42"."SAISIE_ACHAT"."IDSOURCE" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."SAISIE_ACHAT"
    join "OpenConcerto42"."BON_RECEPTION" on "OpenConcerto42"."BON_RECEPTION"."ID" = "OpenConcerto42"."SAISIE_ACHAT"."IDSOURCE"
   where "OpenConcerto42"."SAISIE_ACHAT"."SOURCE" = 'BON_RECEPTION' and ("OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" = 1) and "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."SAISIE_ACHAT"."ID" > 1 and "OpenConcerto42"."BON_RECEPTION"."ID" > 1 and "OpenConcerto42"."SAISIE_ACHAT"."IDSOURCE" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."SAISIE_ACHAT"
    join "OpenConcerto42"."TR_COMMANDE" on "OpenConcerto42"."TR_COMMANDE"."ID_SAISIE_ACHAT" = "OpenConcerto42"."SAISIE_ACHAT"."ID"
    join "OpenConcerto42"."COMMANDE" on "OpenConcerto42"."COMMANDE"."ID" = "OpenConcerto42"."TR_COMMANDE"."ID_COMMANDE"
   where ("OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" = 1) and "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."TR_COMMANDE"."ID_SAISIE_ACHAT" > 1 and "OpenConcerto42"."TR_COMMANDE"."ID_COMMANDE" > 1
     and "OpenConcerto42"."SAISIE_ACHAT"."ID" > 1 and "OpenConcerto42"."COMMANDE"."ID" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."BON_RECEPTION"
    join "OpenConcerto42"."TR_COMMANDE" on "OpenConcerto42"."TR_COMMANDE"."ID_BON_RECEPTION" = "OpenConcerto42"."BON_RECEPTION"."ID"
    join "OpenConcerto42"."COMMANDE" on "OpenConcerto42"."COMMANDE"."ID" = "OpenConcerto42"."TR_COMMANDE"."ID_COMMANDE"
   where ("OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" = 1) and "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."TR_COMMANDE"."ID_BON_RECEPTION" > 1 and "OpenConcerto42"."TR_COMMANDE"."ID_COMMANDE" > 1
     and "OpenConcerto42"."BON_RECEPTION"."ID" > 1 and "OpenConcerto42"."COMMANDE"."ID" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."FACTURE_FOURNISSEUR"
    join "OpenConcerto42"."TR_COMMANDE" on "OpenConcerto42"."TR_COMMANDE"."ID_FACTURE_FOURNISSEUR" = "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID"
    join "OpenConcerto42"."COMMANDE" on "OpenConcerto42"."COMMANDE"."ID" = "OpenConcerto42"."TR_COMMANDE"."ID_COMMANDE"
   where ("OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" = 1) and "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."TR_COMMANDE"."ID_FACTURE_FOURNISSEUR" > 1 and "OpenConcerto42"."TR_COMMANDE"."ID_COMMANDE" > 1
     and "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID" > 1 and "OpenConcerto42"."COMMANDE"."ID" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."SAISIE_ACHAT"
    join "OpenConcerto42"."TR_BON_RECEPTION" on "OpenConcerto42"."TR_BON_RECEPTION"."ID_SAISIE_ACHAT" = "OpenConcerto42"."SAISIE_ACHAT"."ID"
    join "OpenConcerto42"."BON_RECEPTION" on "OpenConcerto42"."BON_RECEPTION"."ID" = "OpenConcerto42"."TR_BON_RECEPTION"."ID_BON_RECEPTION"
   where ("OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" = 1) and "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."TR_BON_RECEPTION"."ID_SAISIE_ACHAT" > 1 and "OpenConcerto42"."TR_BON_RECEPTION"."ID_BON_RECEPTION" > 1
     and "OpenConcerto42"."SAISIE_ACHAT"."ID" > 1 and "OpenConcerto42"."BON_RECEPTION"."ID" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."FACTURE_FOURNISSEUR"
    join "OpenConcerto42"."TR_BON_RECEPTION" on "OpenConcerto42"."TR_BON_RECEPTION"."ID_FACTURE_FOURNISSEUR" = "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID"
    join "OpenConcerto42"."BON_RECEPTION" on "OpenConcerto42"."BON_RECEPTION"."ID" = "OpenConcerto42"."TR_BON_RECEPTION"."ID_BON_RECEPTION"
   where ("OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" = 1) and "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."TR_BON_RECEPTION"."ID_FACTURE_FOURNISSEUR" > 1 and "OpenConcerto42"."TR_BON_RECEPTION"."ID_BON_RECEPTION" > 1
     and "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID" > 1 and "OpenConcerto42"."BON_RECEPTION"."ID" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."COMMANDE"
    join "OpenConcerto42"."TR_DEVIS" on "OpenConcerto42"."TR_DEVIS"."ID_COMMANDE" = "OpenConcerto42"."COMMANDE"."ID"
    join "OpenConcerto42"."DEVIS" on "OpenConcerto42"."DEVIS"."ID_DEVIS" = "OpenConcerto42"."TR_DEVIS"."ID_DEVIS"
   where ("OpenConcerto42"."COMMANDE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" = 1) and "OpenConcerto42"."DEVIS"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."TR_DEVIS"."ID_COMMANDE" > 1 and "OpenConcerto42"."TR_DEVIS"."ID_DEVIS" > 1
     and "OpenConcerto42"."COMMANDE"."ID" > 1 and "OpenConcerto42"."DEVIS"."ID_DEVIS" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."AVOIR_FOURNISSEUR"
    join "OpenConcerto42"."TR_SAISIE_ACHAT" on "OpenConcerto42"."TR_SAISIE_ACHAT"."ID_AVOIR_FOURNISSEUR" = "OpenConcerto42"."AVOIR_FOURNISSEUR"."ID"
    join "OpenConcerto42"."SAISIE_ACHAT" on "OpenConcerto42"."SAISIE_ACHAT"."ID" = "OpenConcerto42"."TR_SAISIE_ACHAT"."ID_SAISIE_ACHAT"
   where ("OpenConcerto42"."AVOIR_FOURNISSEUR"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."AVOIR_FOURNISSEUR"."ID_AFFAIRE" = 1) and "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."TR_SAISIE_ACHAT"."ID_AVOIR_FOURNISSEUR" > 1 and "OpenConcerto42"."TR_SAISIE_ACHAT"."ID_SAISIE_ACHAT" > 1
     and "OpenConcerto42"."AVOIR_FOURNISSEUR"."ID" > 1 and "OpenConcerto42"."SAISIE_ACHAT"."ID" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."COMMANDE_CLIENT"
    join "OpenConcerto42"."TR_DEVIS" on "OpenConcerto42"."TR_DEVIS"."ID_COMMANDE_CLIENT" = "OpenConcerto42"."COMMANDE_CLIENT"."ID"
    join "OpenConcerto42"."DEVIS" on "OpenConcerto42"."DEVIS"."ID_DEVIS" = "OpenConcerto42"."TR_DEVIS"."ID_DEVIS"
   where ("OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" = 1) and "OpenConcerto42"."DEVIS"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."TR_DEVIS"."ID_COMMANDE_CLIENT" > 1 and "OpenConcerto42"."TR_DEVIS"."ID_DEVIS" > 1
     and "OpenConcerto42"."COMMANDE_CLIENT"."ID" > 1 and "OpenConcerto42"."DEVIS"."ID_DEVIS" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."SAISIE_VENTE_FACTURE"
    join "OpenConcerto42"."TR_DEVIS" on "OpenConcerto42"."TR_DEVIS"."ID_SAISIE_VENTE_FACTURE" = "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID"
    join "OpenConcerto42"."DEVIS" on "OpenConcerto42"."DEVIS"."ID_DEVIS" = "OpenConcerto42"."TR_DEVIS"."ID_DEVIS"
   where ("OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" = 1) and "OpenConcerto42"."DEVIS"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."TR_DEVIS"."ID_SAISIE_VENTE_FACTURE" > 1 and "OpenConcerto42"."TR_DEVIS"."ID_DEVIS" > 1
     and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" > 1 and "OpenConcerto42"."DEVIS"."ID_DEVIS" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."BON_DE_LIVRAISON"
    join "OpenConcerto42"."TR_DEVIS" on "OpenConcerto42"."TR_DEVIS"."ID_BON_DE_LIVRAISON" = "OpenConcerto42"."BON_DE_LIVRAISON"."ID"
    join "OpenConcerto42"."DEVIS" on "OpenConcerto42"."DEVIS"."ID_DEVIS" = "OpenConcerto42"."TR_DEVIS"."ID_DEVIS"
   where ("OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" = 1) and "OpenConcerto42"."DEVIS"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."TR_DEVIS"."ID_BON_DE_LIVRAISON" > 1 and "OpenConcerto42"."TR_DEVIS"."ID_DEVIS" > 1
     and "OpenConcerto42"."BON_DE_LIVRAISON"."ID" > 1 and "OpenConcerto42"."DEVIS"."ID_DEVIS" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."SAISIE_VENTE_FACTURE"
    join "OpenConcerto42"."TR_COMMANDE_CLIENT" on "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_SAISIE_VENTE_FACTURE" = "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID"
    join "OpenConcerto42"."COMMANDE_CLIENT" on "OpenConcerto42"."COMMANDE_CLIENT"."ID" = "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE_CLIENT"
   where ("OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" = 1) and "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_SAISIE_VENTE_FACTURE" > 1 and "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE_CLIENT" > 1
     and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" > 1 and "OpenConcerto42"."COMMANDE_CLIENT"."ID" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."BON_DE_LIVRAISON"
    join "OpenConcerto42"."TR_COMMANDE_CLIENT" on "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_BON_DE_LIVRAISON" = "OpenConcerto42"."BON_DE_LIVRAISON"."ID"
    join "OpenConcerto42"."COMMANDE_CLIENT" on "OpenConcerto42"."COMMANDE_CLIENT"."ID" = "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE_CLIENT"
   where ("OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" = 1) and "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_BON_DE_LIVRAISON" > 1 and "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE_CLIENT" > 1
     and "OpenConcerto42"."BON_DE_LIVRAISON"."ID" > 1 and "OpenConcerto42"."COMMANDE_CLIENT"."ID" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."COMMANDE"
    join "OpenConcerto42"."TR_COMMANDE_CLIENT" on "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE" = "OpenConcerto42"."COMMANDE"."ID"
    join "OpenConcerto42"."COMMANDE_CLIENT" on "OpenConcerto42"."COMMANDE_CLIENT"."ID" = "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE_CLIENT"
   where ("OpenConcerto42"."COMMANDE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" = 1) and "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE" > 1 and "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE_CLIENT" > 1
     and "OpenConcerto42"."COMMANDE"."ID" > 1 and "OpenConcerto42"."COMMANDE_CLIENT"."ID" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."SAISIE_VENTE_FACTURE"
    join "OpenConcerto42"."TR_BON_DE_LIVRAISON" on "OpenConcerto42"."TR_BON_DE_LIVRAISON"."ID_SAISIE_VENTE_FACTURE" = "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID"
    join "OpenConcerto42"."BON_DE_LIVRAISON" on "OpenConcerto42"."BON_DE_LIVRAISON"."ID" = "OpenConcerto42"."TR_BON_DE_LIVRAISON"."ID_BON_DE_LIVRAISON"
   where ("OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" = 1) and "OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."TR_BON_DE_LIVRAISON"."ID_SAISIE_VENTE_FACTURE" > 1 and "OpenConcerto42"."TR_BON_DE_LIVRAISON"."ID_BON_DE_LIVRAISON" > 1
     and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" > 1 and "OpenConcerto42"."BON_DE_LIVRAISON"."ID" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."AVOIR_CLIENT"
    join "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE" on "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_AVOIR_CLIENT" = "OpenConcerto42"."AVOIR_CLIENT"."ID"
    join "OpenConcerto42"."SAISIE_VENTE_FACTURE" on "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" = "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_SAISIE_VENTE_FACTURE"
   where ("OpenConcerto42"."AVOIR_CLIENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."AVOIR_CLIENT"."ID_AFFAIRE" = 1) and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_AVOIR_CLIENT" > 1 and "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_SAISIE_VENTE_FACTURE" > 1
     and "OpenConcerto42"."AVOIR_CLIENT"."ID" > 1 and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."BON_DE_LIVRAISON"
    join "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE" on "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_BON_DE_LIVRAISON" = "OpenConcerto42"."BON_DE_LIVRAISON"."ID"
    join "OpenConcerto42"."SAISIE_VENTE_FACTURE" on "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" = "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_SAISIE_VENTE_FACTURE"
   where ("OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" = 1) and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_BON_DE_LIVRAISON" > 1 and "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_SAISIE_VENTE_FACTURE" > 1
     and "OpenConcerto42"."BON_DE_LIVRAISON"."ID" > 1 and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."COMMANDE"
    join "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE" on "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_COMMANDE" = "OpenConcerto42"."COMMANDE"."ID"
    join "OpenConcerto42"."SAISIE_VENTE_FACTURE" on "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" = "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_SAISIE_VENTE_FACTURE"
   where ("OpenConcerto42"."COMMANDE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" = 1) and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" > 1
     and "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_COMMANDE" > 1 and "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_SAISIE_VENTE_FACTURE" > 1
     and "OpenConcerto42"."COMMANDE"."ID" > 1 and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" > 1
) x;
