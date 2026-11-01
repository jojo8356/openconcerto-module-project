-- Une affaire, ses commandes fournisseur et ses factures fournisseur : qui est
-- relie a qui, et qui ne l'est pas.
--
-- Lecture seule.
--
--   docker exec -i C sh -c 'psql -U "$POSTGRES_USER" -d LA_BASE' < sql/factures-affaire-liens.sql
--
-- Le numero d'affaire est '12197' : remplacez-le si besoin.
--
-- But : une facture n'affiche un numero de commande que si un lien de transfert
-- existe (TR_COMMANDE, ou FACTURE_FOURNISSEUR_ELEMENT.ID_COMMANDE_ELEMENT).
-- Ce fichier montre, pour une affaire, les factures qui ont ce lien, celles qui
-- ne l'ont pas, et — pour ces dernieres — la commande qui a les memes montants,
-- afin de savoir si c'est un lien manquant ou une facture sans rapport.

drop table if exists cible;
create temp table cible as select '12197' as numero;

\echo '=== 0. L affaire ==='
select a."ID" as id_affaire, a."NUMERO"
  from "OpenConcerto42"."AFFAIRE" a
 where a."NUMERO" = (select numero from cible);

\echo ''
\echo '=== 1. Commandes de l affaire, avec leurs factures liees ==='
select c."ID"            as id_commande,
       c."NUMERO"        as commande,
       c."DATE"          as date_commande,
       c."T_HT"          as ht_commande,
       c."T_TTC"         as ttc_commande,
       count(t."ID_FACTURE_FOURNISSEUR") filter (where t."ID_FACTURE_FOURNISSEUR" > 1) as factures_liees,
       min(f."NUMERO")                                                                   as premiere_facture
  from "OpenConcerto42"."COMMANDE" c
  left join "OpenConcerto42"."TR_COMMANDE" t
         on t."ID_COMMANDE" = c."ID"
        and t."ID_FACTURE_FOURNISSEUR" > 1
  left join "OpenConcerto42"."FACTURE_FOURNISSEUR" f
         on f."ID" = t."ID_FACTURE_FOURNISSEUR"
 where c."ID_AFFAIRE" = (select "ID" from "OpenConcerto42"."AFFAIRE" where "NUMERO" = (select numero from cible))
 group by c."ID", c."NUMERO", c."DATE", c."T_HT", c."T_TTC"
 order by c."NUMERO";

\echo ''
\echo '=== 2. Factures de l affaire : avec ou sans lien de commande ==='
select f."ID"            as id_facture,
       f."NUMERO"        as facture,
       f."DATE"          as date_facture,
       f."T_HT"          as ht,
       f."T_TTC"         as ttc,
       coalesce(t."ID_COMMANDE", 0)                  as id_commande_liee,
       coalesce(cast(nullif(t."ID_COMMANDE", 1) as text), '') as lien,
       case when exists (select 1 from "OpenConcerto42"."TR_COMMANDE" t2
                          where t2."ID_FACTURE_FOURNISSEUR" = f."ID" and t2."ID_COMMANDE" > 1)
            then 'numero affichable'
            else 'aucun lien : numero impossible a afficher' end as etat
  from "OpenConcerto42"."FACTURE_FOURNISSEUR" f
  left join "OpenConcerto42"."TR_COMMANDE" t
         on t."ID_FACTURE_FOURNISSEUR" = f."ID"
        and t."ID_COMMANDE" > 1
 where f."ID" > 1
   and f."ID_AFFAIRE" = (select "ID" from "OpenConcerto42"."AFFAIRE" where "NUMERO" = (select numero from cible))
 order by f."NUMERO";

\echo ''
\echo '=== 3. Factures SANS lien : quelle commande a les memes montants ? ==='
-- Si une commande de l affaire a exactement le meme HT et le meme TTC, la
-- facture en vient tres probablement, mais le transfert n a pas ete enregistre
-- (facture saisie a la main, ou creee par un autre chemin).
select f."NUMERO"      as facture,
       f."T_HT"        as ht_facture,
       f."T_TTC"       as ttc_facture,
       c."NUMERO"      as commande_meme_montant,
       c."DATE"        as date_commande
  from "OpenConcerto42"."FACTURE_FOURNISSEUR" f
  join "OpenConcerto42"."COMMANDE" c
    on c."T_HT" = f."T_HT" and c."T_TTC" = f."T_TTC"
 where f."ID" > 1
   and f."ID_AFFAIRE" = (select "ID" from "OpenConcerto42"."AFFAIRE" where "NUMERO" = (select numero from cible))
   and not exists (select 1 from "OpenConcerto42"."TR_COMMANDE" t
                    where t."ID_FACTURE_FOURNISSEUR" = f."ID" and t."ID_COMMANDE" > 1)
   and c."ID_AFFAIRE" = f."ID_AFFAIRE"
 order by f."NUMERO";

\echo ''
\echo '=== 4. Resume : combien de factures affichables, combien muettes ==='
select count(*)                                                              as factures_de_l_affaire,
       count(*) filter (where exists (select 1 from "OpenConcerto42"."TR_COMMANDE" t
                                       where t."ID_FACTURE_FOURNISSEUR" = f."ID"
                                         and t."ID_COMMANDE" > 1))            as avec_numero,
       count(*) filter (where not exists (select 1 from "OpenConcerto42"."TR_COMMANDE" t
                                           where t."ID_FACTURE_FOURNISSEUR" = f."ID"
                                             and t."ID_COMMANDE" > 1))        as sans_numero
  from "OpenConcerto42"."FACTURE_FOURNISSEUR" f
 where f."ID" > 1
   and f."ID_AFFAIRE" = (select "ID" from "OpenConcerto42"."AFFAIRE" where "NUMERO" = (select numero from cible));
