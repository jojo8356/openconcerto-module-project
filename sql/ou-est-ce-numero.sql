-- « Ce numero n'existe nulle part » : dans quelle base est-il, et sous quelle forme ?
--
-- Lecture seule. A lancer sur CHAQUE base du conteneur, dans la meme commande :
--
--   for db in OpenConcerto dump1009; do
--     echo "=============== $db"
--     docker exec -i C sh -c "psql -U \"\$POSTGRES_USER\" -d $db" < sql/ou-est-ce-numero.sql
--   done
--
-- Pourquoi : le client n'affiche qu'UNE base a la fois (propriete systemRoot de
-- ~/.config/OpenConcerto/main.properties). Un numero visible dans une liste peut
-- tres bien appartenir a l'autre base — et dans ce cas aucune requete sur la
-- base courante ne le trouvera, ce qui n'a rien a voir avec le rattachement
-- d'affaire.
--
-- Le numero cherche est '12197'. Il est cherche en large ('%12197%') et par ID,
-- car un numero peut porter un suffixe (12085B) ou des espaces.

\echo '=== 0. Quelle base, combien d objets ==='
select current_database() as base,
       (select count(*) from "OpenConcerto42"."AFFAIRE")    as affaires,
       (select count(*) from "OpenConcerto42"."COMMANDE")   as commandes,
       (select count(*) from "OpenConcerto42"."FACTURE_FOURNISSEUR") as factures;

\echo ''
\echo '=== 1. AFFAIRE : numero contenant 12197, ou ID = 12197 ==='
select a."ID", a."NUMERO", a."NOM", length(a."NUMERO") as longueur
  from "OpenConcerto42"."AFFAIRE" a
 where a."NUMERO" like '%12197%' or a."ID" = 12197
 order by a."NUMERO";

\echo ''
\echo '=== 2. COMMANDE fournisseur : numero contenant 12197, ou ID = 12197 ==='
select c."ID", c."NUMERO", c."DATE", c."ID_AFFAIRE", length(c."NUMERO") as longueur
  from "OpenConcerto42"."COMMANDE" c
 where c."NUMERO" like '%12197%' or c."ID" = 12197
 order by c."NUMERO";

\echo ''
\echo '=== 3. Les 15 plus grands numeros d affaire de cette base ==='
select a."ID", a."NUMERO", a."NOM"
  from "OpenConcerto42"."AFFAIRE" a
 where a."ID" > 1
 order by a."NUMERO" desc
 limit 15;

\echo ''
\echo '=== 4. Format des numeros : espaces parasites, min, max ==='
select count(*)                                                 as affaires,
       count(*) filter (where a."NUMERO" <> btrim(a."NUMERO"))   as avec_espaces,
       count(*) filter (where coalesce(a."NUMERO", '') = '')      as sans_numero,
       min(a."NUMERO")                                           as plus_petit,
       max(a."NUMERO")                                           as plus_grand
  from "OpenConcerto42"."AFFAIRE" a
 where a."ID" > 1;

\echo ''
\echo '=== 5. Les 10 dernieres commandes fournisseur de cette base ==='
select c."ID", c."NUMERO", c."DATE", c."ID_AFFAIRE"
  from "OpenConcerto42"."COMMANDE" c
 where c."ID" > 1
 order by c."ID" desc
 limit 10;

\echo ''
\echo '=== 6. Les 10 dernieres affaires creees (ID decroissant) ==='
select a."ID", a."NUMERO", a."NOM"
  from "OpenConcerto42"."AFFAIRE" a
 where a."ID" > 1
 order by a."ID" desc
 limit 10;
