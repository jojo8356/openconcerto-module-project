-- Pourquoi une facture fournisseur de l'affaire 12085 n'apparait pas dans
-- l'onglet « Factures fournisseurs » de « Historique affaires » ?
--
-- Mesure du 30/10 : la base compte **25** factures pour l'affaire 190 (numero
-- 12085), la fenetre en affiche 24. La seule absente est F201240028467.
--
-- Le module ne filtre rien : il confie la liste a OpenConcerto
-- (ListeHistoriquePanel). Si une ligne manque, c'est donc qu'OpenConcerto la
-- masque : etat, annulation, ou date hors periode. Les requetes ci-dessous
-- donnent tout ce qu'il faut pour le prouver.
--
--   docker exec -i openconcerto176-db-1 sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < diagnostic-facture-absente.sql

\echo '=== 1. Colonnes de FACTURE_FOURNISSEUR ==='
select column_name, data_type
  from information_schema.columns
 where table_schema = 'OpenConcerto42' and table_name = 'FACTURE_FOURNISSEUR'
 order by ordinal_position;

\echo ''
\echo '=== 2. La facture absente, en entier ==='
select to_jsonb(f) as facture
  from "OpenConcerto42"."FACTURE_FOURNISSEUR" f
 where f."NUMERO" = 'F201240028467';

\echo ''
\echo '=== 3. Une facture affichee, pour comparer ==='
select to_jsonb(f) as facture
  from "OpenConcerto42"."FACTURE_FOURNISSEUR" f
 where f."NUMERO" = 'F201240023710';

\echo ''
\echo '=== 4. Les 25 factures de l affaire (la ligne 25 doit etre presente ici) ==='
select f."ID", f."NUMERO", f."DATE"
  from "OpenConcerto42"."FACTURE_FOURNISSEUR" f
 where f."ID_AFFAIRE" = (select "ID" from "OpenConcerto42"."AFFAIRE" where "NUMERO" = '12085')
 order by f."NUMERO";
