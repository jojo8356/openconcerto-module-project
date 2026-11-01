-- Diagnostic cible : le combo « Affaire » est grise / la liste des affaires
-- parait vide dans le formulaire d'une commande fournisseur.
--
-- Contexte constate :
--   * AFFAIRE n'a pas de colonne ID_SOCIETE_COMMON  -> filtre societe inactif ;
--   * 384 affaires, dont 255 « En cours », 86 « Dossier clos » ;
--   * l'affaire de la commande 12048-PO-001 (ID 145) est « En cours » -> valide ;
--   * aucun pointeur casse.
-- Restent deux pistes mesurables : les droits, et les affaires sans etat.
--
--   sh scripts/oc-psql.sh -f sql/diagnostic-affaire-combo.sql

\echo '=== A. Affaires sans etat (ID_ETAT_AFFAIRE NULL) : ce que la liste affiche ==='
select count(*) as sans_etat from "OpenConcerto42"."AFFAIRE" where "ID_ETAT_AFFAIRE" is null;
select "ID", "NUMERO", "NOM" from "OpenConcerto42"."AFFAIRE"
 where "ID_ETAT_AFFAIRE" is null order by "ID" desc limit 15;

\echo ''
\echo '=== B. Affaires sans nom (NOM vide) : entree de combo potentiellement vide ==='
select count(*) as sans_nom from "OpenConcerto42"."AFFAIRE" where coalesce("NOM", '') = '';
select count(*) as sans_numero from "OpenConcerto42"."AFFAIRE" where coalesce("NUMERO", '') = '';

\echo ''
\echo '=== C. Droits d''abe, ligne par ligne (ordre = priorite) ==='
select ur."ID" as id_ligne, r."CODE" as code, coalesce(ur."OBJECT", '(tous)') as objet,
       case when ur."HAVE_RIGHT" then 'oui' else 'NON' end as droit
  from "Common"."USER_RIGHT" ur
  join "Common"."USER_COMMON" u on u."ID" = ur."ID_USER_COMMON"
  join "Common"."RIGHT" r on r."ID" = ur."ID_RIGHT"
 where u."LOGIN" = 'abe'
 order by ur."ID";

\echo ''
\echo '=== D. Interdictions explicites (HAVE_RIGHT = false), tous comptes ==='
select u."LOGIN", ur."ID" as id_ligne, r."CODE" as code,
       coalesce(ur."OBJECT", '(tous les objets)') as objet
  from "Common"."USER_RIGHT" ur
  join "Common"."USER_COMMON" u on u."ID" = ur."ID_USER_COMMON"
  join "Common"."RIGHT" r on r."ID" = ur."ID_RIGHT"
 where not ur."HAVE_RIGHT"
 order by u."LOGIN", ur."ID";

\echo ''
\echo '=== E. Compare : abe vs Administrateur (droits accordes) ==='
select r."CODE" as code, coalesce(ur."OBJECT", '(tous)') as objet,
       max(case when u."LOGIN" = 'abe' then case when ur."HAVE_RIGHT" then 'oui' else 'NON' end end) as abe,
       max(case when u."LOGIN" = 'Administrateur' then case when ur."HAVE_RIGHT" then 'oui' else 'NON' end end) as admin
  from "Common"."USER_RIGHT" ur
  join "Common"."USER_COMMON" u on u."ID" = ur."ID_USER_COMMON"
  join "Common"."RIGHT" r on r."ID" = ur."ID_RIGHT"
 where u."LOGIN" in ('abe', 'Administrateur')
 group by 1, 2
 order by 1, 2;

\echo ''
\echo '=== F. Acces aux societes (un compte sans acces ne voit rien de la societe) ==='
select u."LOGIN", s."NOM" as societe, s."ID" as id_societe
  from "Common"."ACCES_SOCIETE" ac
  join "Common"."USER_COMMON" u on u."ID" = ac."ID_USER_COMMON"
  join "Common"."SOCIETE_COMMON" s on s."ID" = ac."ID_SOCIETE_COMMON"
 order by u."LOGIN", s."NOM";
