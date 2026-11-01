-- Controle de l'affaire 12085 : ce que l'onglet « Factures fournisseurs » doit
-- afficher, et ce qui pourrait manquer.
--
-- Lecture seule. Sert a trancher une question simple : l'onglet montre-t-il
-- toutes les factures fournisseur de l'affaire ?
--
--   docker exec -i openconcerto176-db-1 sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < controle-affaire-12085.sql
--
-- Sortie attendue apres la reprise :
--   1. l'affaire visee (son ID, par exemple 190) ;
--   2. le nombre de factures fournisseur rattachees — le meme nombre que les
--      lignes de l'onglet ;
--   3. la liste de ces factures, a comparer avec l'onglet ;
--   4. les factures du meme fournisseur restees sans affaire : c'est la que se
--      trouve une eventuelle facture oubliee (saisie a la main, donc sans
--      document d'origine, la reprise ne peut pas la retrouver).

drop table if exists cible;
create temp table cible as
  select "ID" as id_affaire, "NUMERO", "NOM"
    from "OpenConcerto42"."AFFAIRE"
   where "NUMERO" = '12085';

\echo '=== 1. Affaire visee ==='
select * from cible;

\echo ''
\echo '=== 2. Factures fournisseur rattachees a cette affaire ==='
select count(*) as factures
  from "OpenConcerto42"."FACTURE_FOURNISSEUR" f
  join cible c on c.id_affaire = f."ID_AFFAIRE";

\echo ''
\echo '=== 3. Leur numero (a comparer avec l onglet) ==='
select f."NUMERO"
  from "OpenConcerto42"."FACTURE_FOURNISSEUR" f
  join cible c on c.id_affaire = f."ID_AFFAIRE"
 where f."ID" > 1
 order by f."NUMERO";

\echo ''
\echo '=== 4. Factures des memes fournisseurs, restees sans affaire ==='
select s."NUMERO", s."DATE"
  from "OpenConcerto42"."FACTURE_FOURNISSEUR" s
 where (s."ID_AFFAIRE" is null or s."ID_AFFAIRE" <= 1)
   and s."ID" > 1
   and s."ID_FOURNISSEUR" > 1
   and s."ID_FOURNISSEUR" in (select f."ID_FOURNISSEUR"
                                from "OpenConcerto42"."FACTURE_FOURNISSEUR" f
                                join cible c on c.id_affaire = f."ID_AFFAIRE"
                               where f."ID_FOURNISSEUR" > 1)
 order by s."DATE" desc
 limit 30;
