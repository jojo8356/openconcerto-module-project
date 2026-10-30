-- Historique affaires : ce que la fenetre DEVRAIT afficher pour une affaire.
--
-- Lecture seule. Sert a comparer, onglet par onglet, ce que montre
-- « Historique affaires » avec ce que contient la base. Si un onglet est vide
-- alors que la table correspondante a des lignes ici, c'est un defaut
-- d'affichage ou de lien, pas une absence de donnees.
--
--   sh scripts/oc-psql.sh -f sql/historique-affaire.sql
--
-- >>> Remplacez le numero d'affaire ci-dessous (une seule ligne a changer). <<<
--
-- Les deux requetes ci-dessous regroupent 24 tableaux. Si votre base n'a pas
-- l'une de ces tables, psql nomme la table en erreur : retirez la ligne
-- correspondante, le reste s'affiche quand meme. La cle utilisee est "ID",
-- sauf pour DEVIS ("ID_DEVIS"), mesure sur la base du client.

drop table if exists cible;
create temp table cible as select 11874 as numero;

\echo '=== 0. Affaire visee ==='
select a."ID" as id_affaire, a."NUMERO", a."NOM"
  from "OpenConcerto42"."AFFAIRE" a
 where a."ID" = (select numero from cible);

\echo ''
\echo '=== 1. Nombre de documents par tableau (les onglets de la fenetre) ==='
select 'DEVIS' as tableau, count(*) as documents from "OpenConcerto42"."DEVIS" where ("OpenConcerto42"."DEVIS"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."DEVIS"."ID_AFFAIRE" = 1) and "OpenConcerto42"."DEVIS"."ID_DEVIS" > 1 union all
select 'COMMANDE' as tableau, count(*) as documents from "OpenConcerto42"."COMMANDE" where ("OpenConcerto42"."COMMANDE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" = 1) and "OpenConcerto42"."COMMANDE"."ID" > 1 union all
select 'BON_RECEPTION' as tableau, count(*) as documents from "OpenConcerto42"."BON_RECEPTION" where ("OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" = 1) and "OpenConcerto42"."BON_RECEPTION"."ID" > 1 union all
select 'SAISIE_ACHAT' as tableau, count(*) as documents from "OpenConcerto42"."SAISIE_ACHAT" where ("OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" = 1) and "OpenConcerto42"."SAISIE_ACHAT"."ID" > 1 union all
select 'FACTURE_FOURNISSEUR' as tableau, count(*) as documents from "OpenConcerto42"."FACTURE_FOURNISSEUR" where ("OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" = 1) and "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID" > 1 union all
select 'AVOIR_FOURNISSEUR' as tableau, count(*) as documents from "OpenConcerto42"."AVOIR_FOURNISSEUR" where ("OpenConcerto42"."AVOIR_FOURNISSEUR"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."AVOIR_FOURNISSEUR"."ID_AFFAIRE" = 1) and "OpenConcerto42"."AVOIR_FOURNISSEUR"."ID" > 1 union all
select 'DEMANDE_PRIX' as tableau, count(*) as documents from "OpenConcerto42"."DEMANDE_PRIX" where ("OpenConcerto42"."DEMANDE_PRIX"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."DEMANDE_PRIX"."ID_AFFAIRE" = 1) and "OpenConcerto42"."DEMANDE_PRIX"."ID" > 1 union all
select 'DEMANDE_ACHAT' as tableau, count(*) as documents from "OpenConcerto42"."DEMANDE_ACHAT" where ("OpenConcerto42"."DEMANDE_ACHAT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."DEMANDE_ACHAT"."ID_AFFAIRE" = 1) and "OpenConcerto42"."DEMANDE_ACHAT"."ID" > 1 union all
select 'COMMANDE_CLIENT' as tableau, count(*) as documents from "OpenConcerto42"."COMMANDE_CLIENT" where ("OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" = 1) and "OpenConcerto42"."COMMANDE_CLIENT"."ID" > 1 union all
select 'BON_DE_LIVRAISON' as tableau, count(*) as documents from "OpenConcerto42"."BON_DE_LIVRAISON" where ("OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" = 1) and "OpenConcerto42"."BON_DE_LIVRAISON"."ID" > 1 union all
select 'SAISIE_VENTE_FACTURE' as tableau, count(*) as documents from "OpenConcerto42"."SAISIE_VENTE_FACTURE" where ("OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" = 1) and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" > 1 union all
select 'AVOIR_CLIENT' as tableau, count(*) as documents from "OpenConcerto42"."AVOIR_CLIENT" where ("OpenConcerto42"."AVOIR_CLIENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."AVOIR_CLIENT"."ID_AFFAIRE" = 1) and "OpenConcerto42"."AVOIR_CLIENT"."ID" > 1 union all
select 'COMMANDE_ELEMENT' as tableau, count(*) as documents
  from "OpenConcerto42"."COMMANDE" d join "OpenConcerto42"."COMMANDE_ELEMENT" l on d."ID" = l."ID_COMMANDE"
 where (d."ID_AFFAIRE" IS NULL OR d."ID_AFFAIRE" = 1) and d."ID" > 1 and l."ID_COMMANDE" > 1 union all
select 'FACTURE_FOURNISSEUR_ELEMENT' as tableau, count(*) as documents
  from "OpenConcerto42"."FACTURE_FOURNISSEUR" d join "OpenConcerto42"."FACTURE_FOURNISSEUR_ELEMENT" l on d."ID" = l."ID_FACTURE_FOURNISSEUR"
 where (d."ID_AFFAIRE" IS NULL OR d."ID_AFFAIRE" = 1) and d."ID" > 1 and l."ID_FACTURE_FOURNISSEUR" > 1 union all
select 'BON_RECEPTION_ELEMENT' as tableau, count(*) as documents
  from "OpenConcerto42"."BON_RECEPTION" d join "OpenConcerto42"."BON_RECEPTION_ELEMENT" l on d."ID" = l."ID_BON_RECEPTION"
 where (d."ID_AFFAIRE" IS NULL OR d."ID_AFFAIRE" = 1) and d."ID" > 1 and l."ID_BON_RECEPTION" > 1 union all
select 'DEMANDE_PRIX_ELEMENT' as tableau, count(*) as documents
  from "OpenConcerto42"."DEMANDE_PRIX" d join "OpenConcerto42"."DEMANDE_PRIX_ELEMENT" l on d."ID" = l."ID_DEMANDE_PRIX"
 where (d."ID_AFFAIRE" IS NULL OR d."ID_AFFAIRE" = 1) and d."ID" > 1 and l."ID_DEMANDE_PRIX" > 1 union all
select 'DEMANDE_ACHAT_ELEMENT' as tableau, count(*) as documents
  from "OpenConcerto42"."DEMANDE_ACHAT" d join "OpenConcerto42"."DEMANDE_ACHAT_ELEMENT" l on d."ID" = l."ID_DEMANDE_ACHAT"
 where (d."ID_AFFAIRE" IS NULL OR d."ID_AFFAIRE" = 1) and d."ID" > 1 and l."ID_DEMANDE_ACHAT" > 1 union all
select 'SAISIE_ACHAT_ELEMENT' as tableau, count(*) as documents
  from "OpenConcerto42"."SAISIE_ACHAT" d join "OpenConcerto42"."SAISIE_ACHAT_ELEMENT" l on d."ID" = l."ID_SAISIE_ACHAT"
 where (d."ID_AFFAIRE" IS NULL OR d."ID_AFFAIRE" = 1) and d."ID" > 1 and l."ID_SAISIE_ACHAT" > 1 union all
select 'AVOIR_FOURNISSEUR_ELEMENT' as tableau, count(*) as documents
  from "OpenConcerto42"."AVOIR_FOURNISSEUR" d join "OpenConcerto42"."AVOIR_FOURNISSEUR_ELEMENT" l on d."ID" = l."ID_AVOIR_FOURNISSEUR"
 where (d."ID_AFFAIRE" IS NULL OR d."ID_AFFAIRE" = 1) and d."ID" > 1 and l."ID_AVOIR_FOURNISSEUR" > 1 union all
select 'COMMANDE_CLIENT_ELEMENT' as tableau, count(*) as documents
  from "OpenConcerto42"."COMMANDE_CLIENT" d join "OpenConcerto42"."COMMANDE_CLIENT_ELEMENT" l on d."ID" = l."ID_COMMANDE_CLIENT"
 where (d."ID_AFFAIRE" IS NULL OR d."ID_AFFAIRE" = 1) and d."ID" > 1 and l."ID_COMMANDE_CLIENT" > 1 union all
select 'SAISIE_VENTE_FACTURE_ELEMENT' as tableau, count(*) as documents
  from "OpenConcerto42"."SAISIE_VENTE_FACTURE" d join "OpenConcerto42"."SAISIE_VENTE_FACTURE_ELEMENT" l on d."ID" = l."ID_SAISIE_VENTE_FACTURE"
 where (d."ID_AFFAIRE" IS NULL OR d."ID_AFFAIRE" = 1) and d."ID" > 1 and l."ID_SAISIE_VENTE_FACTURE" > 1 union all
select 'DEVIS_ELEMENT' as tableau, count(*) as documents
  from "OpenConcerto42"."DEVIS" d join "OpenConcerto42"."DEVIS_ELEMENT" l on d."ID_DEVIS" = l."ID_DEVIS"
 where (d."ID_AFFAIRE" IS NULL OR d."ID_AFFAIRE" = 1) and d."ID_DEVIS" > 1 and l."ID_DEVIS" > 1 union all
select 'AVOIR_CLIENT_ELEMENT' as tableau, count(*) as documents
  from "OpenConcerto42"."AVOIR_CLIENT" d join "OpenConcerto42"."AVOIR_CLIENT_ELEMENT" l on d."ID" = l."ID_AVOIR_CLIENT"
 where (d."ID_AFFAIRE" IS NULL OR d."ID_AFFAIRE" = 1) and d."ID" > 1 and l."ID_AVOIR_CLIENT" > 1 union all
select 'BON_DE_LIVRAISON_ELEMENT' as tableau, count(*) as documents
  from "OpenConcerto42"."BON_DE_LIVRAISON" d join "OpenConcerto42"."BON_DE_LIVRAISON_ELEMENT" l on d."ID" = l."ID_BON_DE_LIVRAISON"
 where (d."ID_AFFAIRE" IS NULL OR d."ID_AFFAIRE" = 1) and d."ID" > 1 and l."ID_BON_DE_LIVRAISON" > 1
 order by 2 desc, 1;

\echo ''
\echo '=== 2. Detail des documents de l affaire ==='
select 'DEVIS' as tableau, cast("ID_DEVIS" as text) as id, cast(coalesce("NUMERO", '') as text) as numero
  from "OpenConcerto42"."DEVIS"
 where ("OpenConcerto42"."DEVIS"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."DEVIS"."ID_AFFAIRE" = 1) and "OpenConcerto42"."DEVIS"."ID_DEVIS" > 1 union all
select 'COMMANDE' as tableau, cast("ID" as text) as id, cast(coalesce("NUMERO", '') as text) as numero
  from "OpenConcerto42"."COMMANDE"
 where ("OpenConcerto42"."COMMANDE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" = 1) and "OpenConcerto42"."COMMANDE"."ID" > 1 union all
select 'BON_RECEPTION' as tableau, cast("ID" as text) as id, cast(coalesce("NUMERO", '') as text) as numero
  from "OpenConcerto42"."BON_RECEPTION"
 where ("OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" = 1) and "OpenConcerto42"."BON_RECEPTION"."ID" > 1 union all
select 'SAISIE_ACHAT' as tableau, cast("ID" as text) as id, cast(coalesce("NUMERO", '') as text) as numero
  from "OpenConcerto42"."SAISIE_ACHAT"
 where ("OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" = 1) and "OpenConcerto42"."SAISIE_ACHAT"."ID" > 1 union all
select 'FACTURE_FOURNISSEUR' as tableau, cast("ID" as text) as id, cast(coalesce("NUMERO", '') as text) as numero
  from "OpenConcerto42"."FACTURE_FOURNISSEUR"
 where ("OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" = 1) and "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID" > 1 union all
select 'AVOIR_FOURNISSEUR' as tableau, cast("ID" as text) as id, cast(coalesce("NUMERO", '') as text) as numero
  from "OpenConcerto42"."AVOIR_FOURNISSEUR"
 where ("OpenConcerto42"."AVOIR_FOURNISSEUR"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."AVOIR_FOURNISSEUR"."ID_AFFAIRE" = 1) and "OpenConcerto42"."AVOIR_FOURNISSEUR"."ID" > 1 union all
select 'DEMANDE_PRIX' as tableau, cast("ID" as text) as id, cast(coalesce("NUMERO", '') as text) as numero
  from "OpenConcerto42"."DEMANDE_PRIX"
 where ("OpenConcerto42"."DEMANDE_PRIX"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."DEMANDE_PRIX"."ID_AFFAIRE" = 1) and "OpenConcerto42"."DEMANDE_PRIX"."ID" > 1 union all
select 'DEMANDE_ACHAT' as tableau, cast("ID" as text) as id, cast(coalesce("NUMERO", '') as text) as numero
  from "OpenConcerto42"."DEMANDE_ACHAT"
 where ("OpenConcerto42"."DEMANDE_ACHAT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."DEMANDE_ACHAT"."ID_AFFAIRE" = 1) and "OpenConcerto42"."DEMANDE_ACHAT"."ID" > 1 union all
select 'COMMANDE_CLIENT' as tableau, cast("ID" as text) as id, cast(coalesce("NUMERO", '') as text) as numero
  from "OpenConcerto42"."COMMANDE_CLIENT"
 where ("OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" = 1) and "OpenConcerto42"."COMMANDE_CLIENT"."ID" > 1 union all
select 'BON_DE_LIVRAISON' as tableau, cast("ID" as text) as id, cast(coalesce("NUMERO", '') as text) as numero
  from "OpenConcerto42"."BON_DE_LIVRAISON"
 where ("OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" = 1) and "OpenConcerto42"."BON_DE_LIVRAISON"."ID" > 1 union all
select 'SAISIE_VENTE_FACTURE' as tableau, cast("ID" as text) as id, cast(coalesce("NUMERO", '') as text) as numero
  from "OpenConcerto42"."SAISIE_VENTE_FACTURE"
 where ("OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" = 1) and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" > 1 union all
select 'AVOIR_CLIENT' as tableau, cast("ID" as text) as id, cast(coalesce("NUMERO", '') as text) as numero
  from "OpenConcerto42"."AVOIR_CLIENT"
 where ("OpenConcerto42"."AVOIR_CLIENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."AVOIR_CLIENT"."ID_AFFAIRE" = 1) and "OpenConcerto42"."AVOIR_CLIENT"."ID" > 1 union all
select 'COMMANDE_ELEMENT' as tableau, cast(l."ID" as text) as id, cast(d."ID" as text) as numero
  from "OpenConcerto42"."COMMANDE" d join "OpenConcerto42"."COMMANDE_ELEMENT" l on d."ID" = l."ID_COMMANDE"
 where (d."ID_AFFAIRE" IS NULL OR d."ID_AFFAIRE" = 1) and d."ID" > 1 and l."ID_COMMANDE" > 1 union all
select 'FACTURE_FOURNISSEUR_ELEMENT' as tableau, cast(l."ID" as text) as id, cast(d."ID" as text) as numero
  from "OpenConcerto42"."FACTURE_FOURNISSEUR" d join "OpenConcerto42"."FACTURE_FOURNISSEUR_ELEMENT" l on d."ID" = l."ID_FACTURE_FOURNISSEUR"
 where (d."ID_AFFAIRE" IS NULL OR d."ID_AFFAIRE" = 1) and d."ID" > 1 and l."ID_FACTURE_FOURNISSEUR" > 1 union all
select 'BON_RECEPTION_ELEMENT' as tableau, cast(l."ID" as text) as id, cast(d."ID" as text) as numero
  from "OpenConcerto42"."BON_RECEPTION" d join "OpenConcerto42"."BON_RECEPTION_ELEMENT" l on d."ID" = l."ID_BON_RECEPTION"
 where (d."ID_AFFAIRE" IS NULL OR d."ID_AFFAIRE" = 1) and d."ID" > 1 and l."ID_BON_RECEPTION" > 1 union all
select 'DEMANDE_PRIX_ELEMENT' as tableau, cast(l."ID" as text) as id, cast(d."ID" as text) as numero
  from "OpenConcerto42"."DEMANDE_PRIX" d join "OpenConcerto42"."DEMANDE_PRIX_ELEMENT" l on d."ID" = l."ID_DEMANDE_PRIX"
 where (d."ID_AFFAIRE" IS NULL OR d."ID_AFFAIRE" = 1) and d."ID" > 1 and l."ID_DEMANDE_PRIX" > 1 union all
select 'DEMANDE_ACHAT_ELEMENT' as tableau, cast(l."ID" as text) as id, cast(d."ID" as text) as numero
  from "OpenConcerto42"."DEMANDE_ACHAT" d join "OpenConcerto42"."DEMANDE_ACHAT_ELEMENT" l on d."ID" = l."ID_DEMANDE_ACHAT"
 where (d."ID_AFFAIRE" IS NULL OR d."ID_AFFAIRE" = 1) and d."ID" > 1 and l."ID_DEMANDE_ACHAT" > 1 union all
select 'SAISIE_ACHAT_ELEMENT' as tableau, cast(l."ID" as text) as id, cast(d."ID" as text) as numero
  from "OpenConcerto42"."SAISIE_ACHAT" d join "OpenConcerto42"."SAISIE_ACHAT_ELEMENT" l on d."ID" = l."ID_SAISIE_ACHAT"
 where (d."ID_AFFAIRE" IS NULL OR d."ID_AFFAIRE" = 1) and d."ID" > 1 and l."ID_SAISIE_ACHAT" > 1 union all
select 'AVOIR_FOURNISSEUR_ELEMENT' as tableau, cast(l."ID" as text) as id, cast(d."ID" as text) as numero
  from "OpenConcerto42"."AVOIR_FOURNISSEUR" d join "OpenConcerto42"."AVOIR_FOURNISSEUR_ELEMENT" l on d."ID" = l."ID_AVOIR_FOURNISSEUR"
 where (d."ID_AFFAIRE" IS NULL OR d."ID_AFFAIRE" = 1) and d."ID" > 1 and l."ID_AVOIR_FOURNISSEUR" > 1 union all
select 'COMMANDE_CLIENT_ELEMENT' as tableau, cast(l."ID" as text) as id, cast(d."ID" as text) as numero
  from "OpenConcerto42"."COMMANDE_CLIENT" d join "OpenConcerto42"."COMMANDE_CLIENT_ELEMENT" l on d."ID" = l."ID_COMMANDE_CLIENT"
 where (d."ID_AFFAIRE" IS NULL OR d."ID_AFFAIRE" = 1) and d."ID" > 1 and l."ID_COMMANDE_CLIENT" > 1 union all
select 'SAISIE_VENTE_FACTURE_ELEMENT' as tableau, cast(l."ID" as text) as id, cast(d."ID" as text) as numero
  from "OpenConcerto42"."SAISIE_VENTE_FACTURE" d join "OpenConcerto42"."SAISIE_VENTE_FACTURE_ELEMENT" l on d."ID" = l."ID_SAISIE_VENTE_FACTURE"
 where (d."ID_AFFAIRE" IS NULL OR d."ID_AFFAIRE" = 1) and d."ID" > 1 and l."ID_SAISIE_VENTE_FACTURE" > 1 union all
select 'DEVIS_ELEMENT' as tableau, cast(l."ID" as text) as id, cast(d."ID_DEVIS" as text) as numero
  from "OpenConcerto42"."DEVIS" d join "OpenConcerto42"."DEVIS_ELEMENT" l on d."ID_DEVIS" = l."ID_DEVIS"
 where (d."ID_AFFAIRE" IS NULL OR d."ID_AFFAIRE" = 1) and d."ID_DEVIS" > 1 and l."ID_DEVIS" > 1 union all
select 'AVOIR_CLIENT_ELEMENT' as tableau, cast(l."ID" as text) as id, cast(d."ID" as text) as numero
  from "OpenConcerto42"."AVOIR_CLIENT" d join "OpenConcerto42"."AVOIR_CLIENT_ELEMENT" l on d."ID" = l."ID_AVOIR_CLIENT"
 where (d."ID_AFFAIRE" IS NULL OR d."ID_AFFAIRE" = 1) and d."ID" > 1 and l."ID_AVOIR_CLIENT" > 1 union all
select 'BON_DE_LIVRAISON_ELEMENT' as tableau, cast(l."ID" as text) as id, cast(d."ID" as text) as numero
  from "OpenConcerto42"."BON_DE_LIVRAISON" d join "OpenConcerto42"."BON_DE_LIVRAISON_ELEMENT" l on d."ID" = l."ID_BON_DE_LIVRAISON"
 where (d."ID_AFFAIRE" IS NULL OR d."ID_AFFAIRE" = 1) and d."ID" > 1 and l."ID_BON_DE_LIVRAISON" > 1
 order by 1, 3;
