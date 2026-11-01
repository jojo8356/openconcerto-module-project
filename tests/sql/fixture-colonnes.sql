-- =====================================================================
-- Base de depart du test « libelles de colonnes ».
-- =====================================================================
-- Reproduit ce qui existe forcement dans une base OpenConcerto :
--   * les utilisateurs (USER_COMMON) avec SUPERUSER / ADMIN / IS_ACTIVE ;
--   * les droits accordes (USER_RIGHT) et le catalogue des droits (RIGHT) ;
--   * quelques tables metier dont les colonnes techniques ID_... doivent
--     pouvoir etre renommees.
-- =====================================================================

drop schema if exists "OpenConcerto42" cascade;
create schema "OpenConcerto42";
set search_path to "OpenConcerto42";

create table "RIGHT" (
    "ID" integer primary key,
    "CODE" varchar(64),
    "NOM" varchar(128)
);

create table "USER_COMMON" (
    "ID" integer primary key,
    "NOM" varchar(128),
    "LOGIN" varchar(64),
    "ADMIN" boolean,
    "SUPERUSER" boolean,
    "IS_ACTIVE" boolean
);

create table "USER_RIGHT" (
    "ID" integer primary key,
    "ID_USER_COMMON" integer references "USER_COMMON" ("ID"),
    "ID_RIGHT" integer references "RIGHT" ("ID"),
    "HAVE_RIGHT" boolean
);

-- Tables metier minimales : elles portent les colonnes que Gisèle voit.
create table "AFFAIRE" ("ID" integer primary key, "NUMERO" varchar(64), "NOM" varchar(256), "ID_CLIENT" integer);
create table "CLIENT" ("ID" integer primary key, "NOM" varchar(256));
create table "COMMANDE" ("ID" integer primary key, "NUMERO" varchar(64), "ID_AFFAIRE" integer, "ID_FOURNISSEUR" integer);
create table "FACTURE_FOURNISSEUR" ("ID" integer primary key, "NUMERO" varchar(64), "ID_AFFAIRE" integer, "ID_FOURNISSEUR" integer);

-- ---------------------------------------------------------------------
-- Donnees : une superutilisatrice, deux administratrices, trois utilisatrices
-- ---------------------------------------------------------------------
insert into "RIGHT" ("ID", "CODE", "NOM") values
    (1, 'ADMIN', 'Administration'),
    (2, 'VIEW', 'Consultation'),
    (3, 'EDIT', 'Modification'),
    (4, 'DELETE', 'Suppression'),
    (5, 'EXPORT', 'Export');

-- 1 : superutilisatrice, tous les droits (c'est le « role le plus haut »)
-- 2 : administratrice, 2 droits
-- 3 : administratrice, 1 droit
-- 4 : utilisatrice avec 4 droits (plus que les administratrices, mais pas admin)
-- 5 : utilisatrice avec 1 droit
-- 6 : utilisatrice desactivee, avec 5 droits (ne doit pas compter)
insert into "USER_COMMON" ("ID", "NOM", "LOGIN", "ADMIN", "SUPERUSER", "IS_ACTIVE") values
    (1, 'Gisèle', 'gisele', false, true, true),
    (2, 'Nadia', 'nadia', true, false, true),
    (3, 'Paul', 'paul', true, false, true),
    (4, 'Sophie', 'sophie', false, false, true),
    (5, 'Marc', 'marc', false, false, true),
    (6, 'Ancien compte', 'ancien', false, false, false);

insert into "USER_RIGHT" ("ID", "ID_USER_COMMON", "ID_RIGHT", "HAVE_RIGHT") values
    (1, 1, 1, true),
    (2, 1, 2, true),
    (3, 1, 3, true),
    (4, 1, 4, true),
    (5, 1, 5, true),
    (6, 2, 2, true),
    (7, 2, 3, true),
    (8, 3, 2, true),
    (9, 4, 2, true),
    (10, 4, 3, true),
    (11, 4, 4, true),
    (12, 4, 5, true),
    (13, 5, 2, true),
    (14, 6, 1, true),
    (15, 6, 2, true),
    (16, 6, 3, true),
    (17, 6, 4, true),
    (18, 6, 5, true);
