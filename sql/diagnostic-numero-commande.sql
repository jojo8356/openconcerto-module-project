-- Pourquoi une facture fournisseur n'affiche pas le numero de sa commande.
--
-- Lecture seule.
--
--   sh scripts/oc-psql.sh -f sql/diagnostic-numero-commande.sql
--   docker exec -i C sh -c 'psql -U "$POSTGRES_USER" -d LA_BASE' < sql/diagnostic-numero-commande.sql
--
-- Le numero ci-dessous est un EXEMPLE : remplacez-le par celui que vous cherchez.
-- Il peut designer soit une COMMANDE (sa colonne NUMERO), soit une AFFAIRE
-- (numeros courts du genre 12085, 12197). La section 1 tranche.
--
-- POURQUOI la colonne « N° commande f... » peut rester vide alors que
-- l'affaire, elle, est bien remplie :
--
--   * l'affaire d'une facture est une donnee de la facture (ID_AFFAIRE) :
--     une fois remplie, elle s'affiche toujours ;
--   * le numero de commande, lui, n'est PAS stocke dans la facture : c'est le
--     lien de transfert qui le fournit (table TR_COMMANDE, ou le tableau des
--     lignes via FACTURE_FOURNISSEUR_ELEMENT.ID_COMMANDE_ELEMENT). Si ce lien
--     n'existe pas — facture saisie a la main, ou ligne TR_* qui pointe encore
--     la ligne « Indefini » (ID 1) — il n'y a aucun numero a afficher.
--     Remplir l'affaire ne cree pas ce lien : ce sont deux choses distinctes.
--
-- Ce fichier dit, pour un numero donne, laquelle des deux situations on est.

drop table if exists cible;
create temp table cible as select '12197' as numero;

\echo '=== 0. La facture stocke-t-elle un lien direct vers la commande ? ==='
select column_name
  from information_schema.columns
 where table_schema = 'OpenConcerto42' and table_name = 'FACTURE_FOURNISSEUR'
   and column_name like '%COMMANDE%'
 order by 1;

\echo ''
\echo '=== 1. Le numero cherche : commande, affaire, ou les deux ? ==='
select 'COMMANDE' as objet, c."ID" as id, c."NUMERO" as numero, c."ID_AFFAIRE" as id_affaire
  from "OpenConcerto42"."COMMANDE" c
 where c."NUMERO" = (select numero from cible)
union all
select 'AFFAIRE' as objet, a."ID" as id, a."NUMERO" as numero, a."ID" as id_affaire
  from "OpenConcerto42"."AFFAIRE" a
 where a."NUMERO" = (select numero from cible);

\echo ''
\echo '=== 2. Lien de transfert : combien de lignes TR_COMMANDE pour cette commande ==='
select t."ID"                     as id_tr,
       t."ID_COMMANDE"            as id_commande,
       t."ID_FACTURE_FOURNISSEUR" as id_facture,
       case when t."ID_FACTURE_FOURNISSEUR" <= 1 then 'ligne 1 : pas de facture transferee'
            else 'facture reelle' end as etat
  from "OpenConcerto42"."TR_COMMANDE" t
 where t."ID_COMMANDE" = (select c."ID" from "OpenConcerto42"."COMMANDE" c
                           where c."NUMERO" = (select numero from cible))
 order by t."ID";

\echo ''
\echo '=== 3. Factures qui DOIVENT afficher un numero de commande (lien reel) ==='
select f."ID" as id_facture, f."NUMERO" as facture, c."NUMERO" as commande, f."ID_AFFAIRE"
  from "OpenConcerto42"."FACTURE_FOURNISSEUR" f
  join "OpenConcerto42"."TR_COMMANDE" t on t."ID_FACTURE_FOURNISSEUR" = f."ID"
  join "OpenConcerto42"."COMMANDE" c    on c."ID" = t."ID_COMMANDE"
 where t."ID_COMMANDE" = (select cc."ID" from "OpenConcerto42"."COMMANDE" cc
                           where cc."NUMERO" = (select numero from cible))
   and t."ID_COMMANDE" > 1 and t."ID_FACTURE_FOURNISSEUR" > 1
 order by f."NUMERO";

\echo ''
\echo '=== 4. Factures de la MEME AFFAIRE, sans lien de commande (numero impossible) ==='
-- C'est ici que se trouvent les factures qui « n'affichent pas le numero » :
-- elles portent l'affaire, mais aucun transfert ne les relie a la commande.
select f."ID" as id_facture, f."NUMERO" as facture, f."ID_AFFAIRE" as id_affaire
  from "OpenConcerto42"."FACTURE_FOURNISSEUR" f
 where f."ID" > 1
   and f."ID_AFFAIRE" in (select a."ID" from "OpenConcerto42"."AFFAIRE" a
                          where a."NUMERO" = (select numero from cible))
   and not exists (select 1 from "OpenConcerto42"."TR_COMMANDE" t
                    where t."ID_FACTURE_FOURNISSEUR" = f."ID" and t."ID_COMMANDE" > 1)
 order by f."NUMERO";

\echo ''
\echo '=== 5. Le meme controle par l affaire, s il s agit d une affaire ==='
select c."NUMERO" as commande, c."ID_AFFAIRE",
       count(t."ID")                                              as lignes_tr,
       count(*) filter (where t."ID_FACTURE_FOURNISSEUR" > 1)     as factures_liees,
       count(*) filter (where t."ID_FACTURE_FOURNISSEUR" <= 1)    as sans_facture
  from "OpenConcerto42"."COMMANDE" c
  left join "OpenConcerto42"."TR_COMMANDE" t on t."ID_COMMANDE" = c."ID"
 where c."ID_AFFAIRE" in (select a."ID" from "OpenConcerto42"."AFFAIRE" a
                          where a."NUMERO" = (select numero from cible))
   and c."ID" > 1
 group by c."NUMERO", c."ID_AFFAIRE"
 order by c."NUMERO";
