-- Dernières commandes fournisseur d'une base : lesquelles ont été creees ou
-- modifiees le plus recemment, et quelle affaire elles portent.
--
-- Lecture seule.
--
--   docker exec -i openconcerto176-db-1 sh -c 'psql -U "$POSTGRES_USER" -d dump1009' < derniere-commande-fournisseur.sql
--
-- Pourquoi la forme `to_jsonb(c) -> 'COLONNE'` : selon la version et la societe,
-- les colonnes d'audit d'OpenConcerto ne s'appellent pas toujours pareil
-- (MODIFICATION_DATE, CREATION_DATE, ID_USER_COMMON_MODIFY...). Lire la ligne
-- en JSON permet de trier sur l'une ou l'autre SANS erreur si elle n'existe pas
-- (la cle absente vaut NULL). Aucune requete ne casse selon le schema.
--
-- Sections :
--   0. les colonnes de COMMANDE, pour savoir quelles infos d'audit existent ;
--   1. les 15 dernieres commandes, triees sur la modification puis la creation
--      puis l'ID (la plus recente en premier) ;
--   2. la meme chose en resume : numero, date, fournisseur, affaire, auteur ;
--   3. la toute derniere, seule ;
--   4. celles qui n'ont pas d'affaire (les candidates a un rattachement).

\echo '=== 0. Colonnes de COMMANDE (infos d audit disponibles) ==='
select column_name, data_type
  from information_schema.columns
 where table_schema = 'OpenConcerto42' and table_name = 'COMMANDE'
   and (column_name like '%DATE%' or column_name like '%USER%' or column_name like '%CREATE%'
        or column_name like '%MODIF%' or column_name in ('ID', 'NUMERO', 'ID_AFFAIRE', 'DATE'))
 order by ordinal_position;

\echo ''
\echo '=== 1. Les 15 dernieres commandes fournisseur (modifiee, creee, puis ID) ==='
select c."ID",
       c."NUMERO"                                              as numero,
       c."DATE"                                                 as date_document,
       to_jsonb(c) ->> 'CREATION_DATE'                          as creee_le,
       to_jsonb(c) ->> 'MODIFICATION_DATE'                      as modifiee_le,
       to_jsonb(c) ->> 'ID_USER_COMMON_CREATE'                  as id_createur,
       to_jsonb(c) ->> 'ID_USER_COMMON_MODIFY'                  as id_modificateur,
       c."ID_AFFAIRE"                                           as id_affaire,
       a."NUMERO"                                               as numero_affaire
  from "OpenConcerto42"."COMMANDE" c
  left join "OpenConcerto42"."AFFAIRE" a on a."ID" = c."ID_AFFAIRE"
 where c."ID" > 1
 order by coalesce(to_jsonb(c) ->> 'MODIFICATION_DATE',
                   to_jsonb(c) ->> 'CREATION_DATE') desc nulls last,
          c."ID" desc
 limit 15;

\echo ''
\echo '=== 2. Resume : numero, date, fournisseur, affaire, auteur ==='
-- Le fournisseur est lu dans la ligne (pas de jointure sur FOURNISSEUR : cette
-- table n'existe pas dans toutes les bases, et son numero peut etre vide).
select c."ID",
       c."NUMERO"                                        as numero,
       c."DATE"                                          as date_document,
       to_jsonb(c) ->> 'ID_FOURNISSEUR'                  as id_fournisseur,
       coalesce(a."NUMERO", '(aucune)')                  as affaire,
       to_jsonb(c) ->> 'ID_USER_COMMON_MODIFY'           as modifiee_par,
       to_jsonb(c) ->> 'MODIFICATION_DATE'               as modifiee_le
  from "OpenConcerto42"."COMMANDE" c
  left join "OpenConcerto42"."AFFAIRE" a on a."ID" = c."ID_AFFAIRE"
 where c."ID" > 1
 order by coalesce(to_jsonb(c) ->> 'MODIFICATION_DATE',
                   to_jsonb(c) ->> 'CREATION_DATE') desc nulls last,
          c."ID" desc
 limit 15;

\echo ''
\echo '=== 3. La toute derniere, seule ==='
select c."ID", c."NUMERO", c."DATE", c."ID_AFFAIRE",
       to_jsonb(c) ->> 'MODIFICATION_DATE' as modifiee_le,
       to_jsonb(c) ->> 'CREATION_DATE'     as creee_le
  from "OpenConcerto42"."COMMANDE" c
 where c."ID" > 1
 order by coalesce(to_jsonb(c) ->> 'MODIFICATION_DATE',
                   to_jsonb(c) ->> 'CREATION_DATE') desc nulls last,
          c."ID" desc
 limit 1;

\echo ''
\echo '=== 4. Commandes fournisseur sans affaire (dernieres d abord) ==='
select c."ID", c."NUMERO", c."DATE", c."ID_AFFAIRE"
  from "OpenConcerto42"."COMMANDE" c
 where c."ID" > 1
   and (c."ID_AFFAIRE" is null or c."ID_AFFAIRE" <= 1)
 order by c."ID" desc
 limit 20;
