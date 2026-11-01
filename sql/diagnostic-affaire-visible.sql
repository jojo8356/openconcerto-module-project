-- Diagnostic : « l'affaire ne peut pas être vue / choisie » dans OpenConcerto.
--
-- Contexte : l'affaire est bien enregistrée sur le document (colonne
-- ID_AFFAIRE renseignée), mais le champ « Affaire » apparaît grisé dans le
-- formulaire et/ou la liste des affaires est vide.
--
-- À lancer avec :
--   sh scripts/oc-psql.sh -f sql/diagnostic-affaire-visible.sql
--
-- Adapter le schéma société si besoin (OpenConcerto42 chez KINETIC-THERM) :
--   select table_schema from information_schema.tables where table_name = 'AFFAIRE';

\echo '=== 0. Colonnes de AFFAIRE ==='
\echo '(le module ne crée ID_SOCIETE_COMMON que si la colonne existe déjà :'
\echo '   if absent, le filtre societe ne s applique pas : ce n est pas la cause'
select column_name, data_type
  from information_schema.columns
 where table_schema = 'OpenConcerto42' and table_name = 'AFFAIRE'
 order by ordinal_position;

\echo ''
\echo '=== 1. Nombre d''affaires, répartition par état ==='
\echo '(DOSSIER_CLOS = 6 : la liste de gauche les masque quand'
\echo ' « Masquer dossiers clos » est coché, ce qui est le défaut)'
select count(*) as affaires from "OpenConcerto42"."AFFAIRE";

select coalesce(e."NOM", '(état inconnu)') as etat, a."ID_ETAT_AFFAIRE", count(*) as affaires
  from "OpenConcerto42"."AFFAIRE" a
  left join "OpenConcerto42"."ETAT_AFFAIRE" e on e."ID" = a."ID_ETAT_AFFAIRE"
 group by 1, 2 order by 3 desc;

\echo ''
\echo '=== 2. Les 10 dernières affaires (ce que la liste devrait montrer) ==='
select "ID", "NUMERO", "NOM", "ID_ETAT_AFFAIRE"
  from "OpenConcerto42"."AFFAIRE"
 order by "ID" desc limit 10;

\echo ''
\echo '=== 3. La commande fournisseur de la capture et son affaire ==='
select c."ID" as cmd_id, c."NUMERO" as commande, c."ID_AFFAIRE",
       a."NUMERO" as affaire_numero, a."NOM" as affaire_nom,
       a."ID_ETAT_AFFAIRE",
       case when c."ID_AFFAIRE" is null or c."ID_AFFAIRE" <= 1 then 'AUCUNE AFFAIRE sur la commande'
            when a."ID" is null then 'AFFAIRE INEXISTANTE (pointeur casse)'
            else 'OK' end as verdict
  from "OpenConcerto42"."COMMANDE" c
  left join "OpenConcerto42"."AFFAIRE" a on a."ID" = c."ID_AFFAIRE"
 where c."NUMERO" like '12048%'
 order by c."NUMERO";

\echo ''
\echo '=== 4. Documents pointant vers une affaire qui n''existe pas ==='
select 'COMMANDE' as table_doc, count(*) as lignes
  from "OpenConcerto42"."COMMANDE" c
 where c."ID_AFFAIRE" > 1
   and not exists (select 1 from "OpenConcerto42"."AFFAIRE" a where a."ID" = c."ID_AFFAIRE")
union all
select 'FACTURE_FOURNISSEUR', count(*)
  from "OpenConcerto42"."FACTURE_FOURNISSEUR" f
 where f."ID_AFFAIRE" > 1
   and not exists (select 1 from "OpenConcerto42"."AFFAIRE" a where a."ID" = f."ID_AFFAIRE");

\echo ''
\echo '=== 5. Les comptes (droits globaux) ==='
select "ID", "LOGIN", "NOM", "PRENOM", "ADMIN", "SUPERUSER"
  from "Common"."USER_COMMON"
 order by "ID";

\echo ''
\echo '=== 6. Droits explicites portant sur AFFAIRE ==='
select u."LOGIN", r."CODE" as droit, ur."OBJECT", ur."HAVE_RIGHT", ur."ID" as id_ligne
  from "Common"."USER_RIGHT" ur
  join "Common"."USER_COMMON" u on u."ID" = ur."ID_USER_COMMON"
  join "Common"."RIGHT" r on r."ID" = ur."ID_RIGHT"
 where upper(coalesce(ur."OBJECT", '')) like '%AFFAIRE%'
 order by u."LOGIN", r."CODE";

\echo ''
\echo '=== 7. Nombre de lignes de droits par utilisateur (0 = aucun droit explicite) ==='
select u."ID", u."LOGIN", count(ur."ID") as lignes_droits
  from "Common"."USER_COMMON" u
  left join "Common"."USER_RIGHT" ur on ur."ID_USER_COMMON" = u."ID"
 group by u."ID", u."LOGIN"
 order by u."ID";

\echo ''
\echo '=== 8. Droits detailles de chaque compte (code, objet, valeur) ==='
\echo 'Regle du coeur (UserRightsManager.expand) : pour un couple code/objet,'
\echo 'la ligne d ID le plus BAS gagne ; OBJECT NULL = tous les objets.'
select u."LOGIN", ur."ID" as id_ligne, r."CODE" as code, ur."OBJECT",
       case when ur."HAVE_RIGHT" then 'oui' else 'NON' end as droit
  from "Common"."USER_RIGHT" ur
  join "Common"."USER_COMMON" u on u."ID" = ur."ID_USER_COMMON"
  join "Common"."RIGHT" r on r."ID" = ur."ID_RIGHT"
 where u."LOGIN" in ('abe', 'Administrateur', 'erp')
 order by u."LOGIN", r."CODE", ur."ID";

\echo ''
\echo '=== 9. Codes de droits qui INTERDISENT quelque chose (HAVE_RIGHT = false) ==='
\echo 'Une interdiction explicite sur AFFAIRE ou sur tous les objets suffit'
\echo 'a vider le combo de selection des affaires.'
select u."LOGIN", ur."ID" as id_ligne, r."CODE" as code,
       coalesce(ur."OBJECT", '(tous les objets)') as objet
  from "Common"."USER_RIGHT" ur
  join "Common"."USER_COMMON" u on u."ID" = ur."ID_USER_COMMON"
  join "Common"."RIGHT" r on r."ID" = ur."ID_RIGHT"
 where not ur."HAVE_RIGHT"
 order by u."LOGIN", ur."ID";

\echo ''
\echo '=== 10. Acces aux societes ==='
select u."LOGIN", s."NOM" as societe
  from "Common"."ACCES_SOCIETE" ac
  join "Common"."USER_COMMON" u on u."ID" = ac."ID_USER_COMMON"
  join "Common"."SOCIETE_COMMON" s on s."ID" = ac."ID_SOCIETE_COMMON"
 order by u."LOGIN", s."NOM";
