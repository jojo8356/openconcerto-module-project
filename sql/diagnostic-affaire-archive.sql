-- Diagnostic : l'affaire d'un document est-elle proposee dans le menu deroulant ?
--
-- Constat : le menu deroulant propose 343 entrees alors que la base contient
-- 384 lignes dans AFFAIRE (dont la ligne « indefinie » ID 1). Il manque donc
-- ~41 affaires. La cause la plus probable : les affaires ARCHIVEES, que le
-- coeur exclut des listes deroulantes (il n'affiche que les lignes non
-- archivees). Si l'affaire d'un document est archivee, elle sort de la liste :
-- le champ apparait alors grise, avec la valeur « hors liste ».
--
--   sh scripts/oc-psql.sh -f sql/diagnostic-affaire-archive.sql

\echo '=== 1. Repartition par etat d archivage (ARCHIVE) ==='
select coalesce("ARCHIVE"::text, 'NULL') as archive, count(*) as affaires
  from "OpenConcerto42"."AFFAIRE"
 group by 1 order by 2 desc;

\echo ''
\echo '=== 2. Combien d affaires seraient proposees si seules les non archivees comptent ==='
select count(*) as attendues_non_archivees
  from "OpenConcerto42"."AFFAIRE"
 where "ID" > 1 and coalesce("ARCHIVE", 0) = 0;

\echo ''
\echo '=== 3. L affaire 145 (celle de la commande 12048-PO-001) en detail ==='
select "ID", "NUMERO", "NOM", "ID_ETAT_AFFAIRE", "ARCHIVE", "ID_CLIENT", "DATE"
  from "OpenConcerto42"."AFFAIRE" where "ID" = 145;

\echo ''
\echo '=== 4. Les documents de l affaire 145 et l etat de cette affaire ==='
select c."NUMERO" as commande, c."ID_AFFAIRE", a."NUMERO" as affaire,
       a."ID_ETAT_AFFAIRE", coalesce(a."ARCHIVE"::text, 'NULL') as archive
  from "OpenConcerto42"."COMMANDE" c
  left join "OpenConcerto42"."AFFAIRE" a on a."ID" = c."ID_AFFAIRE"
 where c."ID_AFFAIRE" = 145
 order by c."NUMERO" limit 10;

\echo ''
\echo '=== 5. Les 15 affaires les plus recentes : archivees ou non ? ==='
select "ID", "NUMERO", coalesce(nullif("NOM", ''), '(sans nom)') as nom,
       coalesce("ARCHIVE"::text, 'NULL') as archive, "ID_ETAT_AFFAIRE"
  from "OpenConcerto42"."AFFAIRE"
 where "ID" > 1
 order by "ID" desc limit 15;
