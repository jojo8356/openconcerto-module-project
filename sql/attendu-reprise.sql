-- Le nombre que « Aide > Reprendre les affaires des documents » doit annoncer.
--
-- Lecture seule. A executer AVANT la reprise, puis a comparer avec le nombre
-- affiche par la fenetre de confirmation. Les deux doivent etre egaux : s'ils
-- different, c'est la lecture du schema par le module qui est en cause.
--
-- Ne sont comptes que les documents dont l'affaire est VIDE (NULL ou
-- « Indefini » = 1) alors que leur source porte une VRAIE affaire (> 1).
-- Un document saisi a la main, sans document d'origine, n'est jamais compte.
--
--   sh scripts/oc-psql.sh -f sql/attendu-reprise.sql
--   docker exec -i NOM_DU_CONTENEUR sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < sql/attendu-reprise.sql
--
-- Le detail, cas par cas, est dans sql/diagnostic-affaire-transfert.sql.

select sum(documents) as total_a_reprendre from (
  select count(*) as documents from "OpenConcerto42"."SAISIE_ACHAT"
    join "OpenConcerto42"."COMMANDE" on "OpenConcerto42"."COMMANDE"."ID" = "OpenConcerto42"."SAISIE_ACHAT"."IDSOURCE"
   where "OpenConcerto42"."SAISIE_ACHAT"."SOURCE" = 'COMMANDE' and ("OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" = 1) and "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."SAISIE_ACHAT"
    join "OpenConcerto42"."BON_RECEPTION" on "OpenConcerto42"."BON_RECEPTION"."ID" = "OpenConcerto42"."SAISIE_ACHAT"."IDSOURCE"
   where "OpenConcerto42"."SAISIE_ACHAT"."SOURCE" = 'BON_RECEPTION' and ("OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" = 1) and "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."SAISIE_ACHAT"
    join "OpenConcerto42"."TR_COMMANDE" on "OpenConcerto42"."TR_COMMANDE"."ID_SAISIE_ACHAT" = "OpenConcerto42"."SAISIE_ACHAT"."ID"
    join "OpenConcerto42"."COMMANDE" on "OpenConcerto42"."COMMANDE"."ID" = "OpenConcerto42"."TR_COMMANDE"."ID_COMMANDE"
   where ("OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" = 1) and "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."BON_RECEPTION"
    join "OpenConcerto42"."TR_COMMANDE" on "OpenConcerto42"."TR_COMMANDE"."ID_BON_RECEPTION" = "OpenConcerto42"."BON_RECEPTION"."ID"
    join "OpenConcerto42"."COMMANDE" on "OpenConcerto42"."COMMANDE"."ID" = "OpenConcerto42"."TR_COMMANDE"."ID_COMMANDE"
   where ("OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" = 1) and "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."FACTURE_FOURNISSEUR"
    join "OpenConcerto42"."TR_COMMANDE" on "OpenConcerto42"."TR_COMMANDE"."ID_FACTURE_FOURNISSEUR" = "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID"
    join "OpenConcerto42"."COMMANDE" on "OpenConcerto42"."COMMANDE"."ID" = "OpenConcerto42"."TR_COMMANDE"."ID_COMMANDE"
   where ("OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" = 1) and "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."SAISIE_ACHAT"
    join "OpenConcerto42"."TR_BON_RECEPTION" on "OpenConcerto42"."TR_BON_RECEPTION"."ID_SAISIE_ACHAT" = "OpenConcerto42"."SAISIE_ACHAT"."ID"
    join "OpenConcerto42"."BON_RECEPTION" on "OpenConcerto42"."BON_RECEPTION"."ID" = "OpenConcerto42"."TR_BON_RECEPTION"."ID_BON_RECEPTION"
   where ("OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" = 1) and "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."FACTURE_FOURNISSEUR"
    join "OpenConcerto42"."TR_BON_RECEPTION" on "OpenConcerto42"."TR_BON_RECEPTION"."ID_FACTURE_FOURNISSEUR" = "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID"
    join "OpenConcerto42"."BON_RECEPTION" on "OpenConcerto42"."BON_RECEPTION"."ID" = "OpenConcerto42"."TR_BON_RECEPTION"."ID_BON_RECEPTION"
   where ("OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."FACTURE_FOURNISSEUR"."ID_AFFAIRE" = 1) and "OpenConcerto42"."BON_RECEPTION"."ID_AFFAIRE" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."COMMANDE"
    join "OpenConcerto42"."TR_DEVIS" on "OpenConcerto42"."TR_DEVIS"."ID_COMMANDE" = "OpenConcerto42"."COMMANDE"."ID"
    join "OpenConcerto42"."DEVIS" on "OpenConcerto42"."DEVIS"."ID_DEVIS" = "OpenConcerto42"."TR_DEVIS"."ID_DEVIS"
   where ("OpenConcerto42"."COMMANDE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" = 1) and "OpenConcerto42"."DEVIS"."ID_AFFAIRE" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."AVOIR_FOURNISSEUR"
    join "OpenConcerto42"."TR_SAISIE_ACHAT" on "OpenConcerto42"."TR_SAISIE_ACHAT"."ID_AVOIR_FOURNISSEUR" = "OpenConcerto42"."AVOIR_FOURNISSEUR"."ID"
    join "OpenConcerto42"."SAISIE_ACHAT" on "OpenConcerto42"."SAISIE_ACHAT"."ID" = "OpenConcerto42"."TR_SAISIE_ACHAT"."ID_SAISIE_ACHAT"
   where ("OpenConcerto42"."AVOIR_FOURNISSEUR"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."AVOIR_FOURNISSEUR"."ID_AFFAIRE" = 1) and "OpenConcerto42"."SAISIE_ACHAT"."ID_AFFAIRE" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."COMMANDE_CLIENT"
    join "OpenConcerto42"."TR_DEVIS" on "OpenConcerto42"."TR_DEVIS"."ID_COMMANDE_CLIENT" = "OpenConcerto42"."COMMANDE_CLIENT"."ID"
    join "OpenConcerto42"."DEVIS" on "OpenConcerto42"."DEVIS"."ID_DEVIS" = "OpenConcerto42"."TR_DEVIS"."ID_DEVIS"
   where ("OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" = 1) and "OpenConcerto42"."DEVIS"."ID_AFFAIRE" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."SAISIE_VENTE_FACTURE"
    join "OpenConcerto42"."TR_DEVIS" on "OpenConcerto42"."TR_DEVIS"."ID_SAISIE_VENTE_FACTURE" = "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID"
    join "OpenConcerto42"."DEVIS" on "OpenConcerto42"."DEVIS"."ID_DEVIS" = "OpenConcerto42"."TR_DEVIS"."ID_DEVIS"
   where ("OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" = 1) and "OpenConcerto42"."DEVIS"."ID_AFFAIRE" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."BON_DE_LIVRAISON"
    join "OpenConcerto42"."TR_DEVIS" on "OpenConcerto42"."TR_DEVIS"."ID_BON_DE_LIVRAISON" = "OpenConcerto42"."BON_DE_LIVRAISON"."ID"
    join "OpenConcerto42"."DEVIS" on "OpenConcerto42"."DEVIS"."ID_DEVIS" = "OpenConcerto42"."TR_DEVIS"."ID_DEVIS"
   where ("OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" = 1) and "OpenConcerto42"."DEVIS"."ID_AFFAIRE" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."SAISIE_VENTE_FACTURE"
    join "OpenConcerto42"."TR_COMMANDE_CLIENT" on "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_SAISIE_VENTE_FACTURE" = "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID"
    join "OpenConcerto42"."COMMANDE_CLIENT" on "OpenConcerto42"."COMMANDE_CLIENT"."ID" = "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE_CLIENT"
   where ("OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" = 1) and "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."BON_DE_LIVRAISON"
    join "OpenConcerto42"."TR_COMMANDE_CLIENT" on "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_BON_DE_LIVRAISON" = "OpenConcerto42"."BON_DE_LIVRAISON"."ID"
    join "OpenConcerto42"."COMMANDE_CLIENT" on "OpenConcerto42"."COMMANDE_CLIENT"."ID" = "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE_CLIENT"
   where ("OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" = 1) and "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."COMMANDE"
    join "OpenConcerto42"."TR_COMMANDE_CLIENT" on "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE" = "OpenConcerto42"."COMMANDE"."ID"
    join "OpenConcerto42"."COMMANDE_CLIENT" on "OpenConcerto42"."COMMANDE_CLIENT"."ID" = "OpenConcerto42"."TR_COMMANDE_CLIENT"."ID_COMMANDE_CLIENT"
   where ("OpenConcerto42"."COMMANDE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" = 1) and "OpenConcerto42"."COMMANDE_CLIENT"."ID_AFFAIRE" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."SAISIE_VENTE_FACTURE"
    join "OpenConcerto42"."TR_BON_DE_LIVRAISON" on "OpenConcerto42"."TR_BON_DE_LIVRAISON"."ID_SAISIE_VENTE_FACTURE" = "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID"
    join "OpenConcerto42"."BON_DE_LIVRAISON" on "OpenConcerto42"."BON_DE_LIVRAISON"."ID" = "OpenConcerto42"."TR_BON_DE_LIVRAISON"."ID_BON_DE_LIVRAISON"
   where ("OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" = 1) and "OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."AVOIR_CLIENT"
    join "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE" on "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_AVOIR_CLIENT" = "OpenConcerto42"."AVOIR_CLIENT"."ID"
    join "OpenConcerto42"."SAISIE_VENTE_FACTURE" on "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" = "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_SAISIE_VENTE_FACTURE"
   where ("OpenConcerto42"."AVOIR_CLIENT"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."AVOIR_CLIENT"."ID_AFFAIRE" = 1) and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."BON_DE_LIVRAISON"
    join "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE" on "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_BON_DE_LIVRAISON" = "OpenConcerto42"."BON_DE_LIVRAISON"."ID"
    join "OpenConcerto42"."SAISIE_VENTE_FACTURE" on "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" = "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_SAISIE_VENTE_FACTURE"
   where ("OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."BON_DE_LIVRAISON"."ID_AFFAIRE" = 1) and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" > 1
  union all
  select count(*) as documents from "OpenConcerto42"."COMMANDE"
    join "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE" on "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_COMMANDE" = "OpenConcerto42"."COMMANDE"."ID"
    join "OpenConcerto42"."SAISIE_VENTE_FACTURE" on "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID" = "OpenConcerto42"."TR_SAISIE_VENTE_FACTURE"."ID_SAISIE_VENTE_FACTURE"
   where ("OpenConcerto42"."COMMANDE"."ID_AFFAIRE" IS NULL OR "OpenConcerto42"."COMMANDE"."ID_AFFAIRE" = 1) and "OpenConcerto42"."SAISIE_VENTE_FACTURE"."ID_AFFAIRE" > 1
) x;
