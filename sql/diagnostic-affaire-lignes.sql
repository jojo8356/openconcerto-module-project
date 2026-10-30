-- Diagnostic des TABLEAUX DE LIGNES (fichier a part).
--
-- Lecture seule. A executer seulement apres avoir verifie, avec la requete
-- ci-dessous, que le tableau porte bien la colonne ID_AFFAIRE.
--
--   sh scripts/oc-psql.sh -f sql/diagnostic-affaire-lignes.sql

\echo '=== 0. Tableaux de lignes qui portent la colonne ID_AFFAIRE ==='
select table_name
  from information_schema.columns
 where table_schema = 'OpenConcerto42' and column_name = 'ID_AFFAIRE'
   and table_name like '%_ELEMENT'
 order by 1;

\echo ''
\echo '=== 1. Lignes sans affaire, alors que leur document en a une ==='

select 'COMMANDE_ELEMENT' as table_lignes, count(*) as lignes
  from "OpenConcerto42"."COMMANDE_ELEMENT"
  join "OpenConcerto42"."COMMANDE" on "OpenConcerto42"."COMMANDE"."ID" = "OpenConcerto42"."COMMANDE_ELEMENT"."ID_COMMANDE"
 where ("OpenConcerto42"."COMMANDE_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE_ELEMENT"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" > 1 union all
select 'FACTURE_FOURNISSEUR_ELEMENT' as table_lignes, count(*) as lignes
  from "OpenConcerto42"."FACTURE_FOURNISSEUR_ELEMENT"
  join "OpenConcerto42"."FACTURE_FOURNISSEUR" on "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID" = "OpenConcerto42"."FACTURE_FOURNISSEUR_ELEMENT"."ID_FACTURE_FOURNISSEUR"
 where ("OpenConcerto42"."FACTURE_FOURNISSEUR_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."FACTURE_FOURNISSEUR_ELEMENT"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" > 1 union all
select 'BON_RECEPTION_ELEMENT' as table_lignes, count(*) as lignes
  from "OpenConcerto42"."BON_RECEPTION_ELEMENT"
  join "OpenConcerto42"."BON_RECEPTION" on "OpenConcerto42"."BON_RECEPTION"."ID" = "OpenConcerto42"."BON_RECEPTION_ELEMENT"."ID_BON_RECEPTION"
 where ("OpenConcerto42"."BON_RECEPTION_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_RECEPTION_ELEMENT"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" > 1 union all
select 'DEMANDE_PRIX_ELEMENT' as table_lignes, count(*) as lignes
  from "OpenConcerto42"."DEMANDE_PRIX_ELEMENT"
  join "OpenConcerto42"."DEMANDE_PRIX" on "OpenConcerto42"."DEMANDE_PRIX"."ID" = "OpenConcerto42"."DEMANDE_PRIX_ELEMENT"."ID_DEMANDE_PRIX"
 where ("OpenConcerto42"."DEMANDE_PRIX_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."DEMANDE_PRIX_ELEMENT"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."DEMANDE_PRIX"."ID_AFFAIRE" > 1 union all
select 'DEMANDE_ACHAT_ELEMENT' as table_lignes, count(*) as lignes
  from "OpenConcerto42"."DEMANDE_ACHAT_ELEMENT"
  join "OpenConcerto42"."DEMANDE_ACHAT" on "OpenConcerto42"."DEMANDE_ACHAT"."ID" = "OpenConcerto42"."DEMANDE_ACHAT_ELEMENT"."ID_DEMANDE_ACHAT"
 where ("OpenConcerto42"."DEMANDE_ACHAT_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."DEMANDE_ACHAT_ELEMENT"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."DEMANDE_ACHAT"."ID_AFFAIRE" > 1 union all
select 'SAISIE_ACHAT_ELEMENT' as table_lignes, count(*) as lignes
  from "OpenConcerto42"."SAISIE_ACHAT_ELEMENT"
  join "OpenConcerto42"."SAISIE_ACHAT" on "OpenConcerto42"."SAISIE_ACHAT"."ID" = "OpenConcerto42"."SAISIE_ACHAT_ELEMENT"."ID_SAISIE_ACHAT"
 where ("OpenConcerto42"."SAISIE_ACHAT_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_ACHAT_ELEMENT"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" > 1 union all
select 'AVOIR_FOURNISSEUR_ELEMENT' as table_lignes, count(*) as lignes
  from "OpenConcerto42"."AVOIR_FOURNISSEUR_ELEMENT"
  join "OpenConcerto42"."AVOIR_FOURNISSEUR" on "OpenConcerto42"."AVOIR_FOURNISSEUR"."ID" = "OpenConcerto42"."AVOIR_FOURNISSEUR_ELEMENT"."ID_AVOIR_FOURNISSEUR"
 where ("OpenConcerto42"."AVOIR_FOURNISSEUR_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."AVOIR_FOURNISSEUR_ELEMENT"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."AVOIR_FOURNISSEUR"."ID_AFFAIRE" > 1 union all
select 'COMMANDE_CLIENT_ELEMENT' as table_lignes, count(*) as lignes
  from "OpenConcerto42"."COMMANDE_CLIENT_ELEMENT"
  join "OpenConcerto42"."COMMANDE_CLIENT" on "OpenConcerto42"."COMMANDE_CLIENT"."ID" = "OpenConcerto42"."COMMANDE_CLIENT_ELEMENT"."ID_COMMANDE_CLIENT"
 where ("OpenConcerto42"."COMMANDE_CLIENT_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE_CLIENT_ELEMENT"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" > 1 union all
select 'SAISIE_VENTE_FACTURE_ELEMENT' as table_lignes, count(*) as lignes
  from "OpenConcerto42"."SAISIE_VENTE_FACTURE_ELEMENT"
  join "OpenConcerto42"."SAISIE_VENTE_FACTURE" on "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" = "OpenConcerto42"."SAISIE_VENTE_FACTURE_ELEMENT"."ID_SAISIE_VENTE_FACTURE"
 where ("OpenConcerto42"."SAISIE_VENTE_FACTURE_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_VENTE_FACTURE_ELEMENT"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" > 1 union all
select 'DEVIS_ELEMENT' as table_lignes, count(*) as lignes
  from "OpenConcerto42"."DEVIS_ELEMENT"
  join "OpenConcerto42"."DEVIS" on "OpenConcerto42"."DEVIS"."ID_DEVIS" = "OpenConcerto42"."DEVIS_ELEMENT"."ID_DEVIS"
 where ("OpenConcerto42"."DEVIS_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."DEVIS_ELEMENT"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."DEVIS"."ID_AFFAIRE" > 1 union all
select 'AVOIR_CLIENT_ELEMENT' as table_lignes, count(*) as lignes
  from "OpenConcerto42"."AVOIR_CLIENT_ELEMENT"
  join "OpenConcerto42"."AVOIR_CLIENT" on "OpenConcerto42"."AVOIR_CLIENT"."ID" = "OpenConcerto42"."AVOIR_CLIENT_ELEMENT"."ID_AVOIR_CLIENT"
 where ("OpenConcerto42"."AVOIR_CLIENT_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."AVOIR_CLIENT_ELEMENT"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."AVOIR_CLIENT"."ID_AFFAIRE" > 1 union all
select 'BON_DE_LIVRAISON_ELEMENT' as table_lignes, count(*) as lignes
  from "OpenConcerto42"."BON_DE_LIVRAISON_ELEMENT"
  join "OpenConcerto42"."BON_DE_LIVRAISON" on "OpenConcerto42"."BON_DE_LIVRAISON"."ID" = "OpenConcerto42"."BON_DE_LIVRAISON_ELEMENT"."ID_BON_DE_LIVRAISON"
 where ("OpenConcerto42"."BON_DE_LIVRAISON_ELEMENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_DE_LIVRAISON_ELEMENT"."ID_AFFAIRE" = 1)
   and "OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" > 1;
