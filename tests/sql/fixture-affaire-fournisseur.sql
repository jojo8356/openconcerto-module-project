-- =====================================================================
-- Etat « installation existante » : la base du client avant correctif.
-- =====================================================================
--
-- Ce fichier reproduit fidelement l'etat decrit par l'audit
-- (docs/audit-affaire-fournisseur.md) :
--
--   * le module est deja installe (install() n'est plus rejoue) ;
--   * COMMANDE (commande fournisseur) n'a PAS de colonne ID_AFFAIRE ;
--   * SAISIE_ACHAT et AVOIR_FOURNISSEUR non plus ;
--   * FACTURE_FOURNISSEUR a la colonne (ajoutee par setupComponents) ;
--   * COMMANDE_ELEMENT a sa propre colonne ID_AFFAIRE (ajoutee par la
--     premiere installation du module), ce qui desactive le filtrage via le
--     document parent : c'est la configuration « ambigue » de l'audit.
--
-- Les identifiants et les cles primaires sont simplifies (ID partout, alors
-- qu'OpenConcerto utilise parfois ID_DEVIS, etc.) : ces tests ne portent que
-- sur le rattachement a une affaire.
-- =====================================================================

drop schema if exists "OpenConcerto42" cascade;
create schema "OpenConcerto42";
set search_path to "OpenConcerto42";

create table "ETAT_AFFAIRE" ("ID" integer primary key, "NOM" varchar(128));
create table "CLIENT" ("ID" integer primary key, "NOM" varchar(256));
create table "FOURNISSEUR" ("ID" integer primary key, "NOM" varchar(256));

create table "AFFAIRE" (
    "ID" integer primary key,
    "NUMERO" varchar(256),
    "NOM" varchar(1024),
    "DATE" date,
    "ID_CLIENT" integer references "CLIENT" ("ID"),
    "ID_ETAT_AFFAIRE" integer references "ETAT_AFFAIRE" ("ID")
);

-- Commande fournisseur : pas de ID_AFFAIRE (etat avant correctif).
create table "COMMANDE" (
    "ID" integer primary key,
    "NUMERO" varchar(256),
    "NOM" varchar(1024),
    "DATE" date,
    "ID_FOURNISSEUR" integer references "FOURNISSEUR" ("ID"),
    "T_HT" bigint,
    "T_TTC" bigint,
    "EN_COURS" boolean,
    "INFOS" varchar(1024)
);

-- Lignes de commande : elles portent leur propre ID_AFFAIRE (piege).
create table "COMMANDE_ELEMENT" (
    "ID" integer primary key,
    "ID_COMMANDE" integer references "COMMANDE" ("ID"),
    "DESIGNATION" varchar(256),
    "QTE" integer,
    "T_PA_HT" numeric(18, 2),
    "ID_AFFAIRE" integer
);

-- Facture fournisseur : la colonne existe deja (setupComponents).
create table "FACTURE_FOURNISSEUR" (
    "ID" integer primary key,
    "NUMERO" varchar(256),
    "NOM" varchar(1024),
    "DATE" date,
    "ID_FOURNISSEUR" integer references "FOURNISSEUR" ("ID"),
    "T_HT" bigint,
    "T_TTC" bigint,
    "INFOS" varchar(1024),
    "ID_AFFAIRE" integer
);

create table "FACTURE_FOURNISSEUR_ELEMENT" (
    "ID" integer primary key,
    "ID_FACTURE_FOURNISSEUR" integer references "FACTURE_FOURNISSEUR" ("ID"),
    "ID_COMMANDE_ELEMENT" integer,
    "DESIGNATION" varchar(256),
    "T_PA_HT" numeric(18, 2)
);

create table "SAISIE_ACHAT" ("ID" integer primary key, "NUMERO" varchar(256), "MONTANT_HT" bigint);
create table "AVOIR_FOURNISSEUR" ("ID" integer primary key, "NUMERO" varchar(256), "MONTANT_HT" bigint, "A_DEDUIRE" boolean);
create table "BON_RECEPTION" ("ID" integer primary key, "NUMERO" varchar(256));
create table "DEMANDE_PRIX" ("ID" integer primary key, "NUMERO" varchar(256));
create table "DEMANDE_ACHAT_ELEMENT" ("ID" integer primary key, "DESIGNATION" varchar(256));
create table "DEVIS" ("ID" integer primary key, "NUMERO" varchar(256));
create table "COMMANDE_CLIENT" ("ID" integer primary key, "NUMERO" varchar(256));
create table "SAISIE_VENTE_FACTURE" ("ID" integer primary key, "NUMERO" varchar(256));
create table "AVOIR_CLIENT" ("ID" integer primary key, "NUMERO" varchar(256));
create table "BON_DE_LIVRAISON" ("ID" integer primary key, "NUMERO" varchar(256));

-- ---------------------------------------------------------------------
-- Donnees
-- ---------------------------------------------------------------------
insert into "ETAT_AFFAIRE" ("ID", "NOM") values (1, 'Indéfini'), (3, 'En cours'), (6, 'Dossier clos');
insert into "CLIENT" ("ID", "NOM") values (1, 'Client test');
insert into "FOURNISSEUR" ("ID", "NOM") values (1, 'Fournisseur test');

-- 1 = ligne technique « Indefini » (jamais affichee)
-- 330 = affaire de travail, 331 = affaire close
insert into "AFFAIRE" ("ID", "NUMERO", "NOM", "DATE", "ID_CLIENT", "ID_ETAT_AFFAIRE") values
    (1, 'INDEFINI', 'Indéfini', null, 1, 1),
    (330, 'AFF-330', 'Affaire 330', '2026-01-15', 1, 3),
    (331, 'AFF-331', 'Affaire 331', '2025-06-01', 1, 6);

-- 100 : commande fournisseur a rattacher a l'affaire 330 (apres migration)
-- 101 : commande sans affaire
-- 102 : commande a rattacher a l'affaire close 331
insert into "COMMANDE" ("ID", "NUMERO", "NOM", "DATE", "ID_FOURNISSEUR", "T_HT", "T_TTC", "EN_COURS", "INFOS") values
    (100, 'CMD-100', 'Commande 100', '2026-01-20', 1, 120000, 144000, true, 'Commande rattachee'),
    (101, 'CMD-101', 'Commande 101', '2026-01-21', 1, 50000, 60000, true, 'Commande sans affaire'),
    (102, 'CMD-102', 'Commande 102', '2026-01-22', 1, 80000, 96000, true, 'Commande close');

-- Lignes de la commande 100 : 3 sans affaire, 1 avec sa propre affaire (331)
insert into "COMMANDE_ELEMENT" ("ID", "ID_COMMANDE", "DESIGNATION", "QTE", "T_PA_HT", "ID_AFFAIRE") values
    (1001, 100, 'Article 1', 2, 100.00, null),
    (1002, 100, 'Article 2', 1, 200.00, null),
    (1003, 100, 'Article 3', 3, 300.00, null),
    (1004, 100, 'Article close', 1, 50.00, 331),
    (1005, 101, 'Article sans affaire', 1, 10.00, null);

-- 200 : facture fournisseur deja rattachee a l'affaire 330
-- 201 : facture qui pointe sur une affaire inexistante (999)
insert into "FACTURE_FOURNISSEUR" ("ID", "NUMERO", "NOM", "DATE", "ID_FOURNISSEUR", "T_HT", "T_TTC", "INFOS", "ID_AFFAIRE") values
    (200, 'FF-200', 'Facture 200', '2026-01-25', 1, 120000, 144000, 'Facture rattachee', 330),
    (201, 'FF-201', 'Facture 201', '2026-01-26', 1, 10000, 12000, 'Affaire supprimee', 999);

insert into "FACTURE_FOURNISSEUR_ELEMENT" ("ID", "ID_FACTURE_FOURNISSEUR", "ID_COMMANDE_ELEMENT", "DESIGNATION", "T_PA_HT") values
    (2001, 200, 1001, 'Article 1', 100.00),
    (2002, 200, 1002, 'Article 2', 200.00);

insert into "SAISIE_ACHAT" ("ID", "NUMERO", "MONTANT_HT") values (300, 'ACHAT-300', 120000);
insert into "AVOIR_FOURNISSEUR" ("ID", "NUMERO", "MONTANT_HT", "A_DEDUIRE") values (400, 'AV-400', 10000, true);
insert into "BON_RECEPTION" ("ID", "NUMERO") values (500, 'BR-500');
insert into "DEMANDE_PRIX" ("ID", "NUMERO") values (600, 'DP-600');
insert into "DEMANDE_ACHAT_ELEMENT" ("ID", "DESIGNATION") values (700, 'Demande 700');
insert into "DEVIS" ("ID", "NUMERO") values (800, 'DEV-800');
insert into "COMMANDE_CLIENT" ("ID", "NUMERO") values (900, 'CC-900');
insert into "SAISIE_VENTE_FACTURE" ("ID", "NUMERO") values (1000, 'VF-1000');
insert into "AVOIR_CLIENT" ("ID", "NUMERO") values (1100, 'AC-1100');
insert into "BON_DE_LIVRAISON" ("ID", "NUMERO") values (1200, 'BL-1200');
