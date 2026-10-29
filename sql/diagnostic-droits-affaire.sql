-- Simulation de la decision du coeur : « Gisele (abe) peut-elle voir la table
-- AFFAIRE ? » et, si non, pourquoi.
--
-- Regles reproduites (code source OpenConcerto 1.7.6) :
--
--   UserRights.canView(table)  ->  TableAllRights.hasRight(SELECT_ROW, table)
--   TableAllRights.expand()    ->  TABLE_ALL_RIGHTS se decompose en
--                                  SELECT_ROW / UPDATE_ROW / INSERT_ROW /
--                                  DELETE_ROW avec l'objet a NULL (= toutes
--                                  les tables)
--   UserRightsManager.haveRight() :
--      1. on regarde les lignes du compte ;
--      2. si AUCUNE ligne ne correspond, on bascule sur le compte « par
--         defaut » (USER_COMMON id 1, login « Indefini ») ;
--      3. pour un couple (code, objet), c'est la ligne d'ID le plus BAS qui
--         l'emporte (expand() ignore les doublons).
--
--   sh scripts/oc-psql.sh -f sql/diagnostic-droits-affaire.sql

\echo '=== 1. Les lignes de droit qui comptent pour voir les tables ==='
\echo '(TABLE_ALL_RIGHTS et SELECT_ROW ; objet NULL = toutes les tables)'
select u."ID" as id_user, u."LOGIN" as login, ur."ID" as id_ligne,
       r."CODE" as code, coalesce(ur."OBJECT", '(toutes les tables)') as objet,
       case when ur."HAVE_RIGHT" then 'oui' else 'NON' end as droit
  from "Common"."USER_RIGHT" ur
  join "Common"."USER_COMMON" u on u."ID" = ur."ID_USER_COMMON"
  join "Common"."RIGHT" r on r."ID" = ur."ID_RIGHT"
 where r."CODE" in ('TABLE_ALL_RIGHTS', 'TABLE_ALL_MODIF_RIGHTS', 'SELECT_ROW', 'UPDATE_ROW', 'INSERT_ROW', 'DELETE_ROW', 'SAVE_ROW')
   and u."ID" in (1, 18)
 order by u."ID", ur."ID";

\echo ''
\echo '=== 2. Le compte « par defaut » (heritage quand le compte n a aucune ligne) ==='
select "ID", "LOGIN", "NOM", "PRENOM", "ADMIN", "SUPERUSER", "IS_ACTIVE"
  from "Common"."USER_COMMON"
 where "ID" = 1;

\echo ''
\echo '=== 3. Verdict pour abe / Administrateur / erp sur quelques tables ==='
\echo 'able = un droit de lecture existe (compte, sinon compte par defaut)'
with droits as (
    select u."ID" as id_user, r."CODE" as code, ur."OBJECT" as objet,
           ur."HAVE_RIGHT" as ok, ur."ID" as id_ligne
      from "Common"."USER_RIGHT" ur
      join "Common"."USER_COMMON" u on u."ID" = ur."ID_USER_COMMON"
      join "Common"."RIGHT" r on r."ID" = ur."ID_RIGHT"
     where u."ID" in (1, 18, 2, 17)
), tables as (
    select unnest(array['AFFAIRE', 'COMMANDE', 'FACTURE_FOURNISSEUR', 'CLIENT', 'COMMANDE_ELEMENT']) as t
), users as (
    select "ID" as id_user, "LOGIN" as login from "Common"."USER_COMMON" where "ID" in (18, 2, 17)
)
select us.login, t.t as table_test,
       coalesce(
         (select d.ok from droits d
           where d.id_user = us.id_user
             and (d.code = 'TABLE_ALL_RIGHTS' or d.code = 'SELECT_ROW')
             and (d.objet is null or d.objet ilike '%' || t.t || '%')
           order by d.id_ligne limit 1),
         (select d.ok from droits d
           where d.id_user = 1
             and (d.code = 'TABLE_ALL_RIGHTS' or d.code = 'SELECT_ROW')
             and (d.objet is null or d.objet ilike '%' || t.t || '%')
           order by d.id_ligne limit 1),
         false
       ) as peut_lire
  from users us cross join tables t
 order by us.login, t.t;

\echo ''
\echo '=== 4. Correction possible : donner TABLE_ALL_RIGHTS a abe ==='
\echo 'Decommenter et adapter (ici en commentaire pour rester en lecture seule) :'
\echo '  insert into "Common"."USER_RIGHT" ("ID_USER_COMMON","ID_RIGHT","OBJECT","HAVE_RIGHT")'
\echo '  select 18, "ID", null, true from "Common"."RIGHT" where "CODE" = '"'"'TABLE_ALL_RIGHTS'"'"';'
select "ID" as id_du_droit, "CODE" from "Common"."RIGHT"
 where "CODE" in ('TABLE_ALL_RIGHTS', 'TABLE_ALL_MODIF_RIGHTS') order by "CODE";
