-- Historique affaires : ce que la fenetre DEVRAIT afficher pour une affaire.
--
-- Lecture seule. Sert a comparer, onglet par onglet, ce que montre
-- « Historique affaires » avec ce que contient la base. Si un onglet est vide
-- alors que la table correspondante a des lignes ici, c'est un defaut
-- d'affichage ou de lien, pas une absence de donnees.
--
-- A executer sur la base du client :
--   sh scripts/oc-psql.sh -f sql/historique-affaire.sql
--
-- >>> Remplacez le numero d'affaire ci-dessous (une seule ligne a changer). <<<

drop table if exists cible;
create temp table cible as select 11874 as numero;

\echo '=== 0. Affaire visee ==='
select a."ID" as id_affaire, a."NUMERO", a."NOM"
  from "OpenConcerto42"."AFFAIRE" a
 where a."ID" = (select numero from cible);

\echo ''
\echo '=== 1. Nombre de documents par tableau (colonnes « ... » de la fenetre) ==='
select 'DEVIS' as table_document, count(*) as documents from "OpenConcerto42"."DEVIS" where "ID_AFFAIRE" = (select numero from cible) union all
select 'COMMANDE' as table_document, count(*) as documents from "OpenConcerto42"."COMMANDE" where "ID_AFFAIRE" = (select numero from cible) union all
select 'BON_RECEPTION' as table_document, count(*) as documents from "OpenConcerto42"."BON_RECEPTION" where "ID_AFFAIRE" = (select numero from cible) union all
select 'SAISIE_ACHAT' as table_document, count(*) as documents from "OpenConcerto42"."SAISIE_ACHAT" where "ID_AFFAIRE" = (select numero from cible) union all
select 'FACTURE_FOURNISSEUR' as table_document, count(*) as documents from "OpenConcerto42"."FACTURE_FOURNISSEUR" where "ID_AFFAIRE" = (select numero from cible) union all
select 'AVOIR_FOURNISSEUR' as table_document, count(*) as documents from "OpenConcerto42"."AVOIR_FOURNISSEUR" where "ID_AFFAIRE" = (select numero from cible) union all
select 'DEMANDE_PRIX' as table_document, count(*) as documents from "OpenConcerto42"."DEMANDE_PRIX" where "ID_AFFAIRE" = (select numero from cible) union all
select 'DEMANDE_ACHAT' as table_document, count(*) as documents from "OpenConcerto42"."DEMANDE_ACHAT" where "ID_AFFAIRE" = (select numero from cible) union all
select 'COMMANDE_CLIENT' as table_document, count(*) as documents from "OpenConcerto42"."COMMANDE_CLIENT" where "ID_AFFAIRE" = (select numero from cible) union all
select 'BON_DE_LIVRAISON' as table_document, count(*) as documents from "OpenConcerto42"."BON_DE_LIVRAISON" where "ID_AFFAIRE" = (select numero from cible) union all
select 'SAISIE_VENTE_FACTURE' as table_document, count(*) as documents from "OpenConcerto42"."SAISIE_VENTE_FACTURE" where "ID_AFFAIRE" = (select numero from cible) union all
select 'AVOIR_CLIENT' as table_document, count(*) as documents from "OpenConcerto42"."AVOIR_CLIENT" where "ID_AFFAIRE" = (select numero from cible) union all
select 'COMMANDE_ELEMENT' as table_document, count(*) as documents
  from "OpenConcerto42"."COMMANDE_ELEMENT" l join "OpenConcerto42"."COMMANDE" d on d."ID" = l."ID_COMMANDE"
 where d."ID_AFFAIRE" = (select numero from cible) union all
select 'BON_RECEPTION_ELEMENT' as table_document, count(*) as documents
  from "OpenConcerto42"."BON_RECEPTION_ELEMENT" l join "OpenConcerto42"."BON_RECEPTION" d on d."ID" = l."ID_BON_RECEPTION"
 where d."ID_AFFAIRE" = (select numero from cible) union all
select 'FACTURE_FOURNISSEUR_ELEMENT' as table_document, count(*) as documents
  from "OpenConcerto42"."FACTURE_FOURNISSEUR_ELEMENT" l join "OpenConcerto42"."FACTURE_FOURNISSEUR" d on d."ID" = l."ID_FACTURE_FOURNISSEUR"
 where d."ID_AFFAIRE" = (select numero from cible) union all
select 'SAISIE_ACHAT_ELEMENT' as table_document, count(*) as documents
  from "OpenConcerto42"."SAISIE_ACHAT_ELEMENT" l join "OpenConcerto42"."SAISIE_ACHAT" d on d."ID" = l."ID_SAISIE_ACHAT"
 where d."ID_AFFAIRE" = (select numero from cible) union all
select 'AVOIR_FOURNISSEUR_ELEMENT' as table_document, count(*) as documents
  from "OpenConcerto42"."AVOIR_FOURNISSEUR_ELEMENT" l join "OpenConcerto42"."AVOIR_FOURNISSEUR" d on d."ID" = l."ID_AVOIR_FOURNISSEUR"
 where d."ID_AFFAIRE" = (select numero from cible) union all
select 'DEMANDE_PRIX_ELEMENT' as table_document, count(*) as documents
  from "OpenConcerto42"."DEMANDE_PRIX_ELEMENT" l join "OpenConcerto42"."DEMANDE_PRIX" d on d."ID" = l."ID_DEMANDE_PRIX"
 where d."ID_AFFAIRE" = (select numero from cible) union all
select 'DEMANDE_ACHAT_ELEMENT' as table_document, count(*) as documents
  from "OpenConcerto42"."DEMANDE_ACHAT_ELEMENT" l join "OpenConcerto42"."DEMANDE_ACHAT" d on d."ID" = l."ID_DEMANDE_ACHAT"
 where d."ID_AFFAIRE" = (select numero from cible) union all
select 'DEVIS_ELEMENT' as table_document, count(*) as documents
  from "OpenConcerto42"."DEVIS_ELEMENT" l join "OpenConcerto42"."DEVIS" d on d."ID" = l."ID_DEVIS"
 where d."ID_AFFAIRE" = (select numero from cible) union all
select 'COMMANDE_CLIENT_ELEMENT' as table_document, count(*) as documents
  from "OpenConcerto42"."COMMANDE_CLIENT_ELEMENT" l join "OpenConcerto42"."COMMANDE_CLIENT" d on d."ID" = l."ID_COMMANDE_CLIENT"
 where d."ID_AFFAIRE" = (select numero from cible) union all
select 'BON_DE_LIVRAISON_ELEMENT' as table_document, count(*) as documents
  from "OpenConcerto42"."BON_DE_LIVRAISON_ELEMENT" l join "OpenConcerto42"."BON_DE_LIVRAISON" d on d."ID" = l."ID_BON_DE_LIVRAISON"
 where d."ID_AFFAIRE" = (select numero from cible) union all
select 'SAISIE_VENTE_FACTURE_ELEMENT' as table_document, count(*) as documents
  from "OpenConcerto42"."SAISIE_VENTE_FACTURE_ELEMENT" l join "OpenConcerto42"."SAISIE_VENTE_FACTURE" d on d."ID" = l."ID_SAISIE_VENTE_FACTURE"
 where d."ID_AFFAIRE" = (select numero from cible) union all
select 'AVOIR_CLIENT_ELEMENT' as table_document, count(*) as documents
  from "OpenConcerto42"."AVOIR_CLIENT_ELEMENT" l join "OpenConcerto42"."AVOIR_CLIENT" d on d."ID" = l."ID_AVOIR_CLIENT"
 where d."ID_AFFAIRE" = (select numero from cible)
 order by 2 desc, 1;

\echo ''
\echo '=== 2. Detail des documents ==='
select 'DEVIS' as table_document, cast("ID" as text) as id, cast(coalesce("NUMERO", '') as text) as numero, cast("ID_AFFAIRE" as text) as id_affaire
  from "OpenConcerto42"."DEVIS"
 where "ID_AFFAIRE" = (select numero from cible) union all
select 'COMMANDE' as table_document, cast("ID" as text) as id, cast(coalesce("NUMERO", '') as text) as numero, cast("ID_AFFAIRE" as text) as id_affaire
  from "OpenConcerto42"."COMMANDE"
 where "ID_AFFAIRE" = (select numero from cible) union all
select 'BON_RECEPTION' as table_document, cast("ID" as text) as id, cast(coalesce("NUMERO", '') as text) as numero, cast("ID_AFFAIRE" as text) as id_affaire
  from "OpenConcerto42"."BON_RECEPTION"
 where "ID_AFFAIRE" = (select numero from cible) union all
select 'SAISIE_ACHAT' as table_document, cast("ID" as text) as id, cast(coalesce("NUMERO", '') as text) as numero, cast("ID_AFFAIRE" as text) as id_affaire
  from "OpenConcerto42"."SAISIE_ACHAT"
 where "ID_AFFAIRE" = (select numero from cible) union all
select 'FACTURE_FOURNISSEUR' as table_document, cast("ID" as text) as id, cast(coalesce("NUMERO", '') as text) as numero, cast("ID_AFFAIRE" as text) as id_affaire
  from "OpenConcerto42"."FACTURE_FOURNISSEUR"
 where "ID_AFFAIRE" = (select numero from cible) union all
select 'AVOIR_FOURNISSEUR' as table_document, cast("ID" as text) as id, cast(coalesce("NUMERO", '') as text) as numero, cast("ID_AFFAIRE" as text) as id_affaire
  from "OpenConcerto42"."AVOIR_FOURNISSEUR"
 where "ID_AFFAIRE" = (select numero from cible) union all
select 'DEMANDE_PRIX' as table_document, cast("ID" as text) as id, cast(coalesce("NUMERO", '') as text) as numero, cast("ID_AFFAIRE" as text) as id_affaire
  from "OpenConcerto42"."DEMANDE_PRIX"
 where "ID_AFFAIRE" = (select numero from cible) union all
select 'DEMANDE_ACHAT' as table_document, cast("ID" as text) as id, cast(coalesce("NUMERO", '') as text) as numero, cast("ID_AFFAIRE" as text) as id_affaire
  from "OpenConcerto42"."DEMANDE_ACHAT"
 where "ID_AFFAIRE" = (select numero from cible) union all
select 'COMMANDE_CLIENT' as table_document, cast("ID" as text) as id, cast(coalesce("NUMERO", '') as text) as numero, cast("ID_AFFAIRE" as text) as id_affaire
  from "OpenConcerto42"."COMMANDE_CLIENT"
 where "ID_AFFAIRE" = (select numero from cible) union all
select 'BON_DE_LIVRAISON' as table_document, cast("ID" as text) as id, cast(coalesce("NUMERO", '') as text) as numero, cast("ID_AFFAIRE" as text) as id_affaire
  from "OpenConcerto42"."BON_DE_LIVRAISON"
 where "ID_AFFAIRE" = (select numero from cible) union all
select 'SAISIE_VENTE_FACTURE' as table_document, cast("ID" as text) as id, cast(coalesce("NUMERO", '') as text) as numero, cast("ID_AFFAIRE" as text) as id_affaire
  from "OpenConcerto42"."SAISIE_VENTE_FACTURE"
 where "ID_AFFAIRE" = (select numero from cible) union all
select 'AVOIR_CLIENT' as table_document, cast("ID" as text) as id, cast(coalesce("NUMERO", '') as text) as numero, cast("ID_AFFAIRE" as text) as id_affaire
  from "OpenConcerto42"."AVOIR_CLIENT"
 where "ID_AFFAIRE" = (select numero from cible) union all
select 'COMMANDE_ELEMENT' as table_document, cast(l."ID" as text) as id, cast(d."ID" as text) as numero, cast(d."ID_AFFAIRE" as text) as id_affaire
  from "OpenConcerto42"."COMMANDE_ELEMENT" l join "OpenConcerto42"."COMMANDE" d on d."ID" = l."ID_COMMANDE"
 where d."ID_AFFAIRE" = (select numero from cible) union all
select 'BON_RECEPTION_ELEMENT' as table_document, cast(l."ID" as text) as id, cast(d."ID" as text) as numero, cast(d."ID_AFFAIRE" as text) as id_affaire
  from "OpenConcerto42"."BON_RECEPTION_ELEMENT" l join "OpenConcerto42"."BON_RECEPTION" d on d."ID" = l."ID_BON_RECEPTION"
 where d."ID_AFFAIRE" = (select numero from cible) union all
select 'FACTURE_FOURNISSEUR_ELEMENT' as table_document, cast(l."ID" as text) as id, cast(d."ID" as text) as numero, cast(d."ID_AFFAIRE" as text) as id_affaire
  from "OpenConcerto42"."FACTURE_FOURNISSEUR_ELEMENT" l join "OpenConcerto42"."FACTURE_FOURNISSEUR" d on d."ID" = l."ID_FACTURE_FOURNISSEUR"
 where d."ID_AFFAIRE" = (select numero from cible) union all
select 'SAISIE_ACHAT_ELEMENT' as table_document, cast(l."ID" as text) as id, cast(d."ID" as text) as numero, cast(d."ID_AFFAIRE" as text) as id_affaire
  from "OpenConcerto42"."SAISIE_ACHAT_ELEMENT" l join "OpenConcerto42"."SAISIE_ACHAT" d on d."ID" = l."ID_SAISIE_ACHAT"
 where d."ID_AFFAIRE" = (select numero from cible) union all
select 'AVOIR_FOURNISSEUR_ELEMENT' as table_document, cast(l."ID" as text) as id, cast(d."ID" as text) as numero, cast(d."ID_AFFAIRE" as text) as id_affaire
  from "OpenConcerto42"."AVOIR_FOURNISSEUR_ELEMENT" l join "OpenConcerto42"."AVOIR_FOURNISSEUR" d on d."ID" = l."ID_AVOIR_FOURNISSEUR"
 where d."ID_AFFAIRE" = (select numero from cible) union all
select 'DEMANDE_PRIX_ELEMENT' as table_document, cast(l."ID" as text) as id, cast(d."ID" as text) as numero, cast(d."ID_AFFAIRE" as text) as id_affaire
  from "OpenConcerto42"."DEMANDE_PRIX_ELEMENT" l join "OpenConcerto42"."DEMANDE_PRIX" d on d."ID" = l."ID_DEMANDE_PRIX"
 where d."ID_AFFAIRE" = (select numero from cible) union all
select 'DEMANDE_ACHAT_ELEMENT' as table_document, cast(l."ID" as text) as id, cast(d."ID" as text) as numero, cast(d."ID_AFFAIRE" as text) as id_affaire
  from "OpenConcerto42"."DEMANDE_ACHAT_ELEMENT" l join "OpenConcerto42"."DEMANDE_ACHAT" d on d."ID" = l."ID_DEMANDE_ACHAT"
 where d."ID_AFFAIRE" = (select numero from cible) union all
select 'DEVIS_ELEMENT' as table_document, cast(l."ID" as text) as id, cast(d."ID" as text) as numero, cast(d."ID_AFFAIRE" as text) as id_affaire
  from "OpenConcerto42"."DEVIS_ELEMENT" l join "OpenConcerto42"."DEVIS" d on d."ID" = l."ID_DEVIS"
 where d."ID_AFFAIRE" = (select numero from cible) union all
select 'COMMANDE_CLIENT_ELEMENT' as table_document, cast(l."ID" as text) as id, cast(d."ID" as text) as numero, cast(d."ID_AFFAIRE" as text) as id_affaire
  from "OpenConcerto42"."COMMANDE_CLIENT_ELEMENT" l join "OpenConcerto42"."COMMANDE_CLIENT" d on d."ID" = l."ID_COMMANDE_CLIENT"
 where d."ID_AFFAIRE" = (select numero from cible) union all
select 'BON_DE_LIVRAISON_ELEMENT' as table_document, cast(l."ID" as text) as id, cast(d."ID" as text) as numero, cast(d."ID_AFFAIRE" as text) as id_affaire
  from "OpenConcerto42"."BON_DE_LIVRAISON_ELEMENT" l join "OpenConcerto42"."BON_DE_LIVRAISON" d on d."ID" = l."ID_BON_DE_LIVRAISON"
 where d."ID_AFFAIRE" = (select numero from cible) union all
select 'SAISIE_VENTE_FACTURE_ELEMENT' as table_document, cast(l."ID" as text) as id, cast(d."ID" as text) as numero, cast(d."ID_AFFAIRE" as text) as id_affaire
  from "OpenConcerto42"."SAISIE_VENTE_FACTURE_ELEMENT" l join "OpenConcerto42"."SAISIE_VENTE_FACTURE" d on d."ID" = l."ID_SAISIE_VENTE_FACTURE"
 where d."ID_AFFAIRE" = (select numero from cible) union all
select 'AVOIR_CLIENT_ELEMENT' as table_document, cast(l."ID" as text) as id, cast(d."ID" as text) as numero, cast(d."ID_AFFAIRE" as text) as id_affaire
  from "OpenConcerto42"."AVOIR_CLIENT_ELEMENT" l join "OpenConcerto42"."AVOIR_CLIENT" d on d."ID" = l."ID_AVOIR_CLIENT"
 where d."ID_AFFAIRE" = (select numero from cible)
 order by 1, 4, 2;

\echo ''
\echo '=== 3. Rappel : documents sans affaire du tout (a reprendre) ==='
select 'COMMANDE' as table_document, count(*) as sans_affaire from "OpenConcerto42"."COMMANDE" where "ID_AFFAIRE" is null or "ID_AFFAIRE" = 1
union all select 'SAISIE_ACHAT', count(*) from "OpenConcerto42"."SAISIE_ACHAT" where "ID_AFFAIRE" is null or "ID_AFFAIRE" = 1
union all select 'FACTURE_FOURNISSEUR', count(*) from "OpenConcerto42"."FACTURE_FOURNISSEUR" where "ID_AFFAIRE" is null or "ID_AFFAIRE" = 1
union all select 'COMMANDE_CLIENT', count(*) from "OpenConcerto42"."COMMANDE_CLIENT" where "ID_AFFAIRE" is null or "ID_AFFAIRE" = 1
union all select 'SAISIE_VENTE_FACTURE', count(*) from "OpenConcerto42"."SAISIE_VENTE_FACTURE" where "ID_AFFAIRE" is null or "ID_AFFAIRE" = 1
order by 2 desc;

drop table if exists cible;
