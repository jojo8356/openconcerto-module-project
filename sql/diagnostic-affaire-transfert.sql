-- Diagnostic : combien de documents ont perdu leur affaire en transfert ?
--
-- Lecture seule. Aucune ecriture.
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
select 'COMMANDE' as source, count(*) as documents
  from "OpenConcerto42"."SAISIE_ACHAT"
  join "OpenConcerto42"."COMMANDE" on "COMMANDE"."ID" = "SAISIE_ACHAT"."IDSOURCE"
 where "SAISIE_ACHAT"."SOURCE" = 'COMMANDE'
   and ("SAISIE_ACHAT"."ID_AFFAIRE" is null or "SAISIE_ACHAT"."ID_AFFAIRE" = 1)
   and "COMMANDE"."ID_AFFAIRE" > 1
union all
select 'BON_RECEPTION', count(*)
  from "OpenConcerto42"."SAISIE_ACHAT"
  join "OpenConcerto42"."BON_RECEPTION" on "BON_RECEPTION"."ID" = "SAISIE_ACHAT"."IDSOURCE"
 where "SAISIE_ACHAT"."SOURCE" = 'BON_RECEPTION'
   and ("SAISIE_ACHAT"."ID_AFFAIRE" is null or "SAISIE_ACHAT"."ID_AFFAIRE" = 1)
   and "BON_RECEPTION"."ID_AFFAIRE" > 1;

\echo ''
\echo '=== 2. Documents sans affaire, mais leur source (table TR_*) en a une ==='
select 'FACTURE_FOURNISSEUR <- COMMANDE' as transfert, count(*) as documents
  from "OpenConcerto42"."FACTURE_FOURNISSEUR"
  join "OpenConcerto42"."TR_COMMANDE" on "TR_COMMANDE"."ID_FACTURE_FOURNISSEUR" = "FACTURE_FOURNISSEUR"."ID"
  join "OpenConcerto42"."COMMANDE" on "COMMANDE"."ID" = "TR_COMMANDE"."ID_COMMANDE"
 where ("FACTURE_FOURNISSEUR"."ID_AFFAIRE" is null or "FACTURE_FOURNISSEUR"."ID_AFFAIRE" = 1)
   and "COMMANDE"."ID_AFFAIRE" > 1
union all
select 'FACTURE_FOURNISSEUR <- BON_RECEPTION', count(*)
  from "OpenConcerto42"."FACTURE_FOURNISSEUR"
  join "OpenConcerto42"."TR_BON_RECEPTION" on "TR_BON_RECEPTION"."ID_FACTURE_FOURNISSEUR" = "FACTURE_FOURNISSEUR"."ID"
  join "OpenConcerto42"."BON_RECEPTION" on "BON_RECEPTION"."ID" = "TR_BON_RECEPTION"."ID_BON_RECEPTION"
 where ("FACTURE_FOURNISSEUR"."ID_AFFAIRE" is null or "FACTURE_FOURNISSEUR"."ID_AFFAIRE" = 1)
   and "BON_RECEPTION"."ID_AFFAIRE" > 1
union all
select 'BON_RECEPTION <- COMMANDE', count(*)
  from "OpenConcerto42"."BON_RECEPTION"
  join "OpenConcerto42"."TR_COMMANDE" on "TR_COMMANDE"."ID_BON_RECEPTION" = "BON_RECEPTION"."ID"
  join "OpenConcerto42"."COMMANDE" on "COMMANDE"."ID" = "TR_COMMANDE"."ID_COMMANDE"
 where ("BON_RECEPTION"."ID_AFFAIRE" is null or "BON_RECEPTION"."ID_AFFAIRE" = 1)
   and "COMMANDE"."ID_AFFAIRE" > 1
union all
select 'SAISIE_VENTE_FACTURE <- COMMANDE_CLIENT', count(*)
  from "OpenConcerto42"."SAISIE_VENTE_FACTURE"
  join "OpenConcerto42"."TR_COMMANDE_CLIENT" on "TR_COMMANDE_CLIENT"."ID_SAISIE_VENTE_FACTURE" = "SAISIE_VENTE_FACTURE"."ID"
  join "OpenConcerto42"."COMMANDE_CLIENT" on "COMMANDE_CLIENT"."ID" = "TR_COMMANDE_CLIENT"."ID_COMMANDE_CLIENT"
 where ("SAISIE_VENTE_FACTURE"."ID_AFFAIRE" is null or "SAISIE_VENTE_FACTURE"."ID_AFFAIRE" = 1)
   and "COMMANDE_CLIENT"."ID_AFFAIRE" > 1;

\echo ''
\echo '=== 3. Lignes sans affaire, alors que leur document en a une ==='
select 'COMMANDE_ELEMENT' as table_lignes, count(*) as lignes
  from "OpenConcerto42"."COMMANDE_ELEMENT"
  join "OpenConcerto42"."COMMANDE" on "COMMANDE"."ID" = "COMMANDE_ELEMENT"."ID_COMMANDE"
 where ("COMMANDE_ELEMENT"."ID_AFFAIRE" is null or "COMMANDE_ELEMENT"."ID_AFFAIRE" = 1)
   and "COMMANDE"."ID_AFFAIRE" > 1
union all
select 'FACTURE_FOURNISSEUR_ELEMENT', count(*)
  from "OpenConcerto42"."FACTURE_FOURNISSEUR_ELEMENT"
  join "OpenConcerto42"."FACTURE_FOURNISSEUR" on "FACTURE_FOURNISSEUR"."ID" = "FACTURE_FOURNISSEUR_ELEMENT"."ID_FACTURE_FOURNISSEUR"
 where ("FACTURE_FOURNISSEUR_ELEMENT"."ID_AFFAIRE" is null or "FACTURE_FOURNISSEUR_ELEMENT"."ID_AFFAIRE" = 1)
   and "FACTURE_FOURNISSEUR"."ID_AFFAIRE" > 1
union all
select 'SAISIE_ACHAT_ELEMENT', count(*)
  from "OpenConcerto42"."SAISIE_ACHAT_ELEMENT"
  join "OpenConcerto42"."SAISIE_ACHAT" on "SAISIE_ACHAT"."ID" = "SAISIE_ACHAT_ELEMENT"."ID_SAISIE_ACHAT"
 where ("SAISIE_ACHAT_ELEMENT"."ID_AFFAIRE" is null or "SAISIE_ACHAT_ELEMENT"."ID_AFFAIRE" = 1)
   and "SAISIE_ACHAT"."ID_AFFAIRE" > 1;

\echo ''
\echo '=== 4. Les tables de transfert presentes dans cette base ==='
select table_name
  from information_schema.tables
 where table_schema = 'OpenConcerto42' and table_name like 'TR\_%'
 order by 1;

\echo ''
\echo '=== 5. Rappel : documents sans affaire, tous cas confondus ==='
select 'COMMANDE' as document, count(*) as sans_affaire from "OpenConcerto42"."COMMANDE" where "ID_AFFAIRE" is null or "ID_AFFAIRE" = 1
union all select 'BON_RECEPTION', count(*) from "OpenConcerto42"."BON_RECEPTION" where "ID_AFFAIRE" is null or "ID_AFFAIRE" = 1
union all select 'SAISIE_ACHAT', count(*) from "OpenConcerto42"."SAISIE_ACHAT" where "ID_AFFAIRE" is null or "ID_AFFAIRE" = 1
union all select 'FACTURE_FOURNISSEUR', count(*) from "OpenConcerto42"."FACTURE_FOURNISSEUR" where "ID_AFFAIRE" is null or "ID_AFFAIRE" = 1
union all select 'COMMANDE_CLIENT', count(*) from "OpenConcerto42"."COMMANDE_CLIENT" where "ID_AFFAIRE" is null or "ID_AFFAIRE" = 1
union all select 'SAISIE_VENTE_FACTURE', count(*) from "OpenConcerto42"."SAISIE_VENTE_FACTURE" where "ID_AFFAIRE" is null or "ID_AFFAIRE" = 1
order by 2 desc;
