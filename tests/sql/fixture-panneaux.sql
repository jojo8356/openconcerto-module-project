--
-- Base de test pour la suite « panneaux » du module project.
--
-- Elle imite la structure d'OpenConcerto 1.7 (tables en MAJUSCULES, dans un
-- schema nomme comme la societe) et contient volontairement quelques
-- anomalies, pour verifier que les tests les detectent :
--
--   * un devis rattache a une affaire inexistante (ID_AFFAIRE = 999) ;
--   * un devis et une commande fournisseur sans affaire (ID_AFFAIRE NULL) ;
--   * une facture fournisseur dont la table d'elements n'a pas la colonne
--     ID_COMMANDE_ELEMENT (le bug de production) ;
--   * un utilisateur (abe) qui a un refus explicite de lecture sur DEVIS.
--
-- Usage : voir tests/sql/e2e-panneaux.sh
--
BEGIN;

CREATE SCHEMA IF NOT EXISTS "OpenConcerto42";
CREATE SCHEMA IF NOT EXISTS "Common";

SET LOCAL search_path TO "OpenConcerto42";

CREATE TABLE "ETAT_AFFAIRE" ("ID" serial PRIMARY KEY, "NOM" varchar(128));
CREATE TABLE "TYPE_AFFAIRE" ("ID" serial PRIMARY KEY, "NOM" varchar(256));
CREATE TABLE "CLIENT" ("ID" serial PRIMARY KEY, "NOM" varchar(256));
CREATE TABLE "COMMERCIAL" ("ID" serial PRIMARY KEY, "NOM" varchar(256));
CREATE TABLE "UNITE_VENTE" ("ID" serial PRIMARY KEY, "CODE" varchar(16));
CREATE TABLE "ARTICLE" ("ID" serial PRIMARY KEY, "NOM" varchar(256));
CREATE TABLE "FAMILLE_ARTICLE" ("ID" serial PRIMARY KEY, "NOM" varchar(256));

CREATE TABLE "AFFAIRE" (
  "ID" serial PRIMARY KEY,
  "NUMERO" varchar(256),
  "NOM" varchar(1024),
  "INFOS" varchar(1024),
  "ID_CLIENT" integer REFERENCES "CLIENT" ("ID"),
  "ID_DEVIS" integer,
  "DATE" date,
  "ID_COMMERCIAL" integer REFERENCES "COMMERCIAL" ("ID"),
  "ID_ETAT_AFFAIRE" integer REFERENCES "ETAT_AFFAIRE" ("ID"),
  "ID_TYPE_AFFAIRE" integer REFERENCES "TYPE_AFFAIRE" ("ID"),
  "ID_SOCIETE_COMMON" integer
);

CREATE TABLE "ETAT_DEVIS" ("ID" serial PRIMARY KEY, "NOM" varchar(128));
-- La table DEVIS n'a pas de colonne « ID » : sa cle primaire s'appelle
-- « ID_DEVIS » (comme en production). Le harnais doit lire la vraie cle
-- dans le catalogue PostgreSQL, et non supposer « ID ».
CREATE TABLE "DEVIS" (
  "ID_DEVIS" serial PRIMARY KEY, "NUMERO" varchar(256), "DATE" date,
  "T_HT" bigint, "T_HA" bigint, "ID_CLIENT" integer REFERENCES "CLIENT" ("ID"),
  "ID_AFFAIRE" integer REFERENCES "AFFAIRE" ("ID"), "ID_ETAT_DEVIS" integer REFERENCES "ETAT_DEVIS" ("ID")
);
CREATE TABLE "DEVIS_ELEMENT" (
  "ID" serial PRIMARY KEY, "ID_DEVIS" integer REFERENCES "DEVIS" ("ID_DEVIS"), "NOM" varchar(256),
  "T_PV_HT" bigint, "ID_UNITE_VENTE" integer REFERENCES "UNITE_VENTE" ("ID"),
  "QTE" numeric, "QTE_UNITAIRE" numeric,
  "ID_ARTICLE" integer REFERENCES "ARTICLE" ("ID"), "ID_FAMILLE_ARTICLE" integer REFERENCES "FAMILLE_ARTICLE" ("ID")
);

CREATE TABLE "COMMANDE_CLIENT" (
  "ID" serial PRIMARY KEY, "NUMERO" varchar(256), "DATE" date, "T_HT" bigint,
  "ID_CLIENT" integer REFERENCES "CLIENT" ("ID"), "ID_AFFAIRE" integer REFERENCES "AFFAIRE" ("ID")
);
CREATE TABLE "COMMANDE_CLIENT_ELEMENT" (
  "ID" serial PRIMARY KEY, "ID_COMMANDE_CLIENT" integer REFERENCES "COMMANDE_CLIENT" ("ID"), "NOM" varchar(256),
  "T_PV_HT" bigint, "ID_UNITE_VENTE" integer REFERENCES "UNITE_VENTE" ("ID"),
  "QTE" numeric, "QTE_UNITAIRE" numeric,
  "ID_ARTICLE" integer REFERENCES "ARTICLE" ("ID"), "ID_FAMILLE_ARTICLE" integer REFERENCES "FAMILLE_ARTICLE" ("ID")
);
CREATE TABLE "CHIFFRAGE_COMMANDE_CLIENT" (
  "ID" serial PRIMARY KEY, "ID_COMMANDE_CLIENT" integer REFERENCES "COMMANDE_CLIENT" ("ID"), "T_PA_HT" numeric
);

CREATE TABLE "SAISIE_VENTE_FACTURE" (
  "ID" serial PRIMARY KEY, "NUMERO" varchar(256), "T_HT" bigint, "T_TTC" bigint,
  "ID_AFFAIRE" integer REFERENCES "AFFAIRE" ("ID")
);
CREATE TABLE "AVOIR_CLIENT" (
  "ID" serial PRIMARY KEY, "NUMERO" varchar(256), "MONTANT_HT" bigint, "A_DEDUIRE" boolean,
  "ID_AFFAIRE" integer REFERENCES "AFFAIRE" ("ID")
);
CREATE TABLE "DEMANDE_PRIX" ("ID" serial PRIMARY KEY, "NUMERO" varchar(256), "ID_AFFAIRE" integer REFERENCES "AFFAIRE" ("ID"));
CREATE TABLE "DEMANDE_ACHAT_ELEMENT" ("ID" serial PRIMARY KEY, "ID_AFFAIRE" integer REFERENCES "AFFAIRE" ("ID"));
CREATE TABLE "BON_DE_LIVRAISON" ("ID" serial PRIMARY KEY, "NUMERO" varchar(256), "ID_AFFAIRE" integer REFERENCES "AFFAIRE" ("ID"));

CREATE TABLE "COMMANDE" (
  "ID" serial PRIMARY KEY, "NUMERO" varchar(256), "T_HT" bigint, "ID_AFFAIRE" integer REFERENCES "AFFAIRE" ("ID")
);
CREATE TABLE "COMMANDE_ELEMENT" (
  "ID" serial PRIMARY KEY, "ID_COMMANDE" integer REFERENCES "COMMANDE" ("ID"), "T_PA_HT" numeric
);
CREATE TABLE "BON_RECEPTION" ("ID" serial PRIMARY KEY, "NUMERO" varchar(256), "ID_AFFAIRE" integer REFERENCES "AFFAIRE" ("ID"));
CREATE TABLE "BON_RECEPTION_ELEMENT" (
  "ID" serial PRIMARY KEY, "ID_BON_RECEPTION" integer REFERENCES "BON_RECEPTION" ("ID"), "ID_COMMANDE_ELEMENT" integer
);
CREATE TABLE "SAISIE_ACHAT" (
  "ID" serial PRIMARY KEY, "NUMERO" varchar(256), "MONTANT_HT" bigint, "ID_AFFAIRE" integer REFERENCES "AFFAIRE" ("ID")
);
CREATE TABLE "FACTURE_FOURNISSEUR" (
  "ID" serial PRIMARY KEY, "NUMERO" varchar(256), "T_HT" bigint, "ID_AFFAIRE" integer REFERENCES "AFFAIRE" ("ID")
);
-- Colonne ID_COMMANDE_ELEMENT VOLONTAIREMENT ABSENTE : c'est le bug de production.
CREATE TABLE "FACTURE_FOURNISSEUR_ELEMENT" (
  "ID" serial PRIMARY KEY, "ID_FACTURE_FOURNISSEUR" integer REFERENCES "FACTURE_FOURNISSEUR" ("ID"), "T_PA_HT" numeric
);
CREATE TABLE "AVOIR_FOURNISSEUR" (
  "ID" serial PRIMARY KEY, "NUMERO" varchar(256), "MONTANT_HT" bigint, "ID_AFFAIRE" integer REFERENCES "AFFAIRE" ("ID")
);

-- Toutes les installations n'ont pas les memes contraintes de cle etrangere
-- sur ID_AFFAIRE : on les retire ici pour pouvoir simuler une ligne
-- rattachee a une affaire inexistante.
ALTER TABLE "DEVIS" DROP CONSTRAINT IF EXISTS "DEVIS_ID_AFFAIRE_fkey";
ALTER TABLE "SAISIE_VENTE_FACTURE" DROP CONSTRAINT IF EXISTS "SAISIE_VENTE_FACTURE_ID_AFFAIRE_fkey";
ALTER TABLE "COMMANDE" DROP CONSTRAINT IF EXISTS "COMMANDE_ID_AFFAIRE_fkey";

INSERT INTO "ETAT_AFFAIRE" ("ID", "NOM") VALUES (1, 'Indéfini'), (2, 'A traiter'), (3, 'En cours'), (4, 'Traitement terminé'),
  (5, 'A facturer'), (6, 'Dossier clos');
INSERT INTO "TYPE_AFFAIRE" ("ID", "NOM") VALUES (1, 'Indéfini');
INSERT INTO "CLIENT" ("ID", "NOM") VALUES (1, 'Client SA'), (2, 'Autre SA');
INSERT INTO "COMMERCIAL" ("ID", "NOM") VALUES (1, 'Yves');
INSERT INTO "UNITE_VENTE" ("ID", "CODE") VALUES (1, 'U');
INSERT INTO "ARTICLE" ("ID", "NOM") VALUES (1, 'Article A');
INSERT INTO "FAMILLE_ARTICLE" ("ID", "NOM") VALUES (1, 'Famille A');
INSERT INTO "ETAT_DEVIS" ("ID", "NOM") VALUES (1, 'En attente'), (2, 'En attente 2'), (3, 'Accepté'), (4, 'Refusé');

-- Affaires : 1 = ligne technique « Indéfini », 2 = en cours, 3 = en cours, 4 = dossier clos.
INSERT INTO "AFFAIRE" ("ID", "NUMERO", "NOM", "ID_CLIENT", "DATE", "ID_COMMERCIAL", "ID_ETAT_AFFAIRE", "ID_TYPE_AFFAIRE")
VALUES (1, NULL, NULL, NULL, NULL, NULL, 1, 1),
       (2, 'A-001', 'Chantier 1', 1, '2026-01-10', 1, 3, 1),
       (3, 'A-002', 'Chantier 2', 2, '2026-02-20', 1, 3, 1),
       (4, 'A-003', 'Dossier clos', 1, '2026-03-01', 1, 6, 1);

INSERT INTO "DEVIS" ("ID_DEVIS", "NUMERO", "DATE", "T_HT", "T_HA", "ID_CLIENT", "ID_AFFAIRE", "ID_ETAT_DEVIS")
VALUES (1, 'D-1', '2026-01-11', 1000, 900, 1, 2, 3),
       (2, 'D-2', '2026-01-12', 500, 450, 1, 2, 3),
       (3, 'D-ORPHELIN', '2026-01-13', 700, 700, 1, 999, 3),
       (4, 'D-SANS-AFFAIRE', '2026-01-14', 300, 300, 2, NULL, 3),
       (5, 'D-EN-ATTENTE', '2026-01-15', 800, 800, 1, 3, 1);

INSERT INTO "DEVIS_ELEMENT" ("ID", "ID_DEVIS", "NOM", "T_PV_HT", "ID_UNITE_VENTE", "QTE", "QTE_UNITAIRE", "ID_ARTICLE", "ID_FAMILLE_ARTICLE")
VALUES (1, 1, 'Article A', 1000, 1, 2, 500, 1, 1), (2, 5, 'Article A', 800, 1, 1, 800, 1, 1);

INSERT INTO "COMMANDE_CLIENT" ("ID", "NUMERO", "DATE", "T_HT", "ID_CLIENT", "ID_AFFAIRE")
VALUES (1, 'C-1', '2026-01-20', 1000, 1, 2), (2, 'C-2', '2026-01-21', 600, 2, 3);

INSERT INTO "COMMANDE_CLIENT_ELEMENT" ("ID", "ID_COMMANDE_CLIENT", "NOM", "T_PV_HT", "ID_UNITE_VENTE", "QTE", "QTE_UNITAIRE", "ID_ARTICLE", "ID_FAMILLE_ARTICLE")
VALUES (1, 1, 'Article A', 1000, 1, 2, 500, 1, 1), (2, 2, 'Article A', 600, 1, 1, 600, 1, 1);

INSERT INTO "CHIFFRAGE_COMMANDE_CLIENT" ("ID", "ID_COMMANDE_CLIENT", "T_PA_HT") VALUES (1, 1, 950);

INSERT INTO "SAISIE_VENTE_FACTURE" ("ID", "NUMERO", "T_HT", "T_TTC", "ID_AFFAIRE")
VALUES (1, 'F-1', 1000, 1200, 2), (2, 'F-2', 600, 720, 3), (3, 'F-SANS-AFFAIRE', 100, 120, NULL);

INSERT INTO "AVOIR_CLIENT" ("ID", "NUMERO", "MONTANT_HT", "A_DEDUIRE", "ID_AFFAIRE")
VALUES (1, 'AV-1', 100, true, 2);

INSERT INTO "DEMANDE_PRIX" ("ID", "NUMERO", "ID_AFFAIRE") VALUES (1, 'DP-1', 2);
INSERT INTO "DEMANDE_ACHAT_ELEMENT" ("ID", "ID_AFFAIRE") VALUES (1, 2);
INSERT INTO "BON_DE_LIVRAISON" ("ID", "NUMERO", "ID_AFFAIRE") VALUES (1, 'BL-1', 2);

INSERT INTO "COMMANDE" ("ID", "NUMERO", "T_HT", "ID_AFFAIRE")
VALUES (1, 'CF-1', 900, 2), (2, 'CF-SANS-AFFAIRE', 100, NULL);
INSERT INTO "COMMANDE_ELEMENT" ("ID", "ID_COMMANDE", "T_PA_HT") VALUES (1, 1, 900), (2, 2, 100);
INSERT INTO "BON_RECEPTION" ("ID", "NUMERO", "ID_AFFAIRE") VALUES (1, 'BR-1', 2);
INSERT INTO "BON_RECEPTION_ELEMENT" ("ID", "ID_BON_RECEPTION", "ID_COMMANDE_ELEMENT") VALUES (1, 1, 1);
INSERT INTO "SAISIE_ACHAT" ("ID", "NUMERO", "MONTANT_HT", "ID_AFFAIRE") VALUES (1, 'A-1', 800, 2);
INSERT INTO "FACTURE_FOURNISSEUR" ("ID", "NUMERO", "T_HT", "ID_AFFAIRE") VALUES (1, 'FF-1', 950, 2);
INSERT INTO "FACTURE_FOURNISSEUR_ELEMENT" ("ID", "ID_FACTURE_FOURNISSEUR", "T_PA_HT") VALUES (1, 1, 950);
INSERT INTO "AVOIR_FOURNISSEUR" ("ID", "NUMERO", "MONTANT_HT", "ID_AFFAIRE") VALUES (1, 'AVF-1', 50, 2);

-- ------------------------------------------------------------------ Common
SET LOCAL search_path TO "Common";
CREATE TABLE "USER_COMMON" (
  "ID" serial PRIMARY KEY, "LOGIN" varchar(64), "NOM" varchar(128), "PRENOM" varchar(128),
  "ADMIN" boolean, "SUPERUSER" boolean, "PASSWORD" varchar(64)
);
CREATE TABLE "RIGHT" ("ID" serial PRIMARY KEY, "CODE" varchar(64), "NOM" varchar(128), "DESCRIPTION" text);
CREATE TABLE "USER_RIGHT" (
  "ID" serial PRIMARY KEY, "ID_USER_COMMON" integer REFERENCES "USER_COMMON" ("ID"),
  "ID_RIGHT" integer REFERENCES "RIGHT" ("ID"), "OBJECT" varchar(256), "HAVE_RIGHT" boolean
);
CREATE TABLE "FWK_UNDEFINED_IDS" ("TABLENAME" varchar(128), "UNDEFINED_ID" integer);

INSERT INTO "USER_COMMON" ("ID", "LOGIN", "NOM", "PRENOM", "ADMIN", "SUPERUSER", "PASSWORD")
VALUES (1, 'Indéfini', 'Indéfini', '', false, true, NULL),
       (17, 'erp', 'POLSINELLI', 'Yves', true, false, NULL),
       (18, 'abe', 'REBSTOCK', 'Gisèle', false, false, NULL);
INSERT INTO "FWK_UNDEFINED_IDS" ("TABLENAME", "UNDEFINED_ID") VALUES ('USER_COMMON', 1);
INSERT INTO "RIGHT" ("ID", "CODE", "NOM") VALUES
  (1, 'TABLE_ALL_RIGHTS', 'Tous les droits'), (2, 'TABLE_ALL_MODIF_RIGHTS', 'Droits de modification'),
  (3, 'LOCK_ADMIN', 'Verrouillage administration'), (4, 'SELECT_ROW', 'Lecture'), (5, 'UPDATE_ROW', 'Modification'),
  (6, 'INSERT_ROW', 'Insertion'), (7, 'DELETE_ROW', 'Suppression');
-- Gisèle a tous les droits, sauf un refus explicite sur la lecture des devis.
-- OpenConcerto applique « la premiere ligne qui correspond gagne » : le
-- refus doit donc porter un ID inferieur a celui du droit general.
INSERT INTO "USER_RIGHT" ("ID", "ID_USER_COMMON", "ID_RIGHT", "OBJECT", "HAVE_RIGHT")
VALUES (1, 18, 4, 'DEVIS', false),
       (2, 18, 1, NULL, true);

COMMIT;
