-- Combien de documents « Aide > Reprendre les affaires » doit-il annoncer ?
--
-- Lecture seule. A executer AVANT la reprise, puis a comparer avec le nombre
-- affiche par la fenetre de confirmation du menu. Les deux doivent etre egaux :
-- s'ils different, c'est la requete ou le module qui se trompe, et il faut me
-- le dire avec les deux chiffres.
--
-- Ne sont comptes que les documents dont l'affaire est VIDE (NULL ou
-- « Indefini » = 1) alors que leur source porte une VRAIE affaire (> 1).
-- Un document saisi a la main, sans document d'origine, n'est jamais compte.
--
--   sh scripts/oc-psql.sh -f sql/attendu-reprise.sql
--   docker exec -i NOM_DU_CONTENEUR sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < sql/attendu-reprise.sql

\echo '=== Ce que Aide > Reprendre les affaires doit annoncer ==='
\echo '(documents reparables = affaire vide MAIS source connue avec une vraie affaire)'

select 'FACTURE_FOURNISSEUR <- COMMANDE' as reprise, count(*) as documents
  from "OpenConcerto42"."FACTURE_FOURNISSEUR" f
  join "OpenConcerto42"."TR_COMMANDE" t on t."ID_FACTURE_FOURNISSEUR" = f."ID"
  join "OpenConcerto42"."COMMANDE" c on c."ID" = t."ID_COMMANDE"
 where (f."ID_AFFAIRE" is null or f."ID_AFFAIRE" = 1) and c."ID_AFFAIRE" > 1
union all
select 'FACTURE_FOURNISSEUR <- BON_RECEPTION', count(*)
  from "OpenConcerto42"."FACTURE_FOURNISSEUR" f
  join "OpenConcerto42"."TR_BON_RECEPTION" t on t."ID_FACTURE_FOURNISSEUR" = f."ID"
  join "OpenConcerto42"."BON_RECEPTION" b on b."ID" = t."ID_BON_RECEPTION"
 where (f."ID_AFFAIRE" is null or f."ID_AFFAIRE" = 1) and b."ID_AFFAIRE" > 1
union all
select 'SAISIE_ACHAT <- COMMANDE (SOURCE)', count(*)
  from "OpenConcerto42"."SAISIE_ACHAT" s
  join "OpenConcerto42"."COMMANDE" c on c."ID" = s."IDSOURCE"
 where s."SOURCE" = 'COMMANDE' and (s."ID_AFFAIRE" is null or s."ID_AFFAIRE" = 1) and c."ID_AFFAIRE" > 1
union all
select 'SAISIE_ACHAT <- BON_RECEPTION (SOURCE)', count(*)
  from "OpenConcerto42"."SAISIE_ACHAT" s
  join "OpenConcerto42"."BON_RECEPTION" b on b."ID" = s."IDSOURCE"
 where s."SOURCE" = 'BON_RECEPTION' and (s."ID_AFFAIRE" is null or s."ID_AFFAIRE" = 1) and b."ID_AFFAIRE" > 1
union all
select 'BON_RECEPTION <- COMMANDE', count(*)
  from "OpenConcerto42"."BON_RECEPTION" b
  join "OpenConcerto42"."TR_COMMANDE" t on t."ID_BON_RECEPTION" = b."ID"
  join "OpenConcerto42"."COMMANDE" c on c."ID" = t."ID_COMMANDE"
 where (b."ID_AFFAIRE" is null or b."ID_AFFAIRE" = 1) and c."ID_AFFAIRE" > 1
union all
select 'COMMANDE_CLIENT <- DEVIS', count(*)
  from "OpenConcerto42"."COMMANDE_CLIENT" cc
  join "OpenConcerto42"."TR_DEVIS" t on t."ID_COMMANDE_CLIENT" = cc."ID"
  join "OpenConcerto42"."DEVIS" d on d."ID" = t."ID_DEVIS"
 where (cc."ID_AFFAIRE" is null or cc."ID_AFFAIRE" = 1) and d."ID_AFFAIRE" > 1
union all
select 'SAISIE_VENTE_FACTURE <- DEVIS', count(*)
  from "OpenConcerto42"."SAISIE_VENTE_FACTURE" f
  join "OpenConcerto42"."TR_DEVIS" t on t."ID_SAISIE_VENTE_FACTURE" = f."ID"
  join "OpenConcerto42"."DEVIS" d on d."ID" = t."ID_DEVIS"
 where (f."ID_AFFAIRE" is null or f."ID_AFFAIRE" = 1) and d."ID_AFFAIRE" > 1
union all
select 'SAISIE_VENTE_FACTURE <- COMMANDE_CLIENT', count(*)
  from "OpenConcerto42"."SAISIE_VENTE_FACTURE" f
  join "OpenConcerto42"."TR_COMMANDE_CLIENT" t on t."ID_SAISIE_VENTE_FACTURE" = f."ID"
  join "OpenConcerto42"."COMMANDE_CLIENT" cc on cc."ID" = t."ID_COMMANDE_CLIENT"
 where (f."ID_AFFAIRE" is null or f."ID_AFFAIRE" = 1) and cc."ID_AFFAIRE" > 1
union all
select 'BON_DE_LIVRAISON <- COMMANDE_CLIENT', count(*)
  from "OpenConcerto42"."BON_DE_LIVRAISON" b
  join "OpenConcerto42"."TR_COMMANDE_CLIENT" t on t."ID_BON_DE_LIVRAISON" = b."ID"
  join "OpenConcerto42"."COMMANDE_CLIENT" cc on cc."ID" = t."ID_COMMANDE_CLIENT"
 where (b."ID_AFFAIRE" is null or b."ID_AFFAIRE" = 1) and cc."ID_AFFAIRE" > 1
union all
select 'COMMANDE <- DEVIS', count(*)
  from "OpenConcerto42"."COMMANDE" c
  join "OpenConcerto42"."TR_DEVIS" t on t."ID_COMMANDE" = c."ID"
  join "OpenConcerto42"."DEVIS" d on d."ID" = t."ID_DEVIS"
 where (c."ID_AFFAIRE" is null or c."ID_AFFAIRE" = 1) and d."ID_AFFAIRE" > 1
union all
select 'AVOIR_FOURNISSEUR <- SAISIE_ACHAT', count(*)
  from "OpenConcerto42"."AVOIR_FOURNISSEUR" a
  join "OpenConcerto42"."TR_SAISIE_ACHAT" t on t."ID_AVOIR_FOURNISSEUR" = a."ID"
  join "OpenConcerto42"."SAISIE_ACHAT" s on s."ID" = t."ID_SAISIE_ACHAT"
 where (a."ID_AFFAIRE" is null or a."ID_AFFAIRE" = 1) and s."ID_AFFAIRE" > 1
union all
select 'AVOIR_CLIENT <- SAISIE_VENTE_FACTURE', count(*)
  from "OpenConcerto42"."AVOIR_CLIENT" a
  join "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE" t on t."ID_AVOIR_CLIENT" = a."ID"
  join "OpenConcerto42"."SAISIE_VENTE_FACTURE" f on f."ID" = t."ID_SAISIE_VENTE_FACTURE"
 where (a."ID_AFFAIRE" is null or a."ID_AFFAIRE" = 1) and f."ID_AFFAIRE" > 1
order by 2 desc;
