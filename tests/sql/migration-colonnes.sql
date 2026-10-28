-- =====================================================================
-- Libelles de colonnes (reference SQL)
-- =====================================================================
--
-- Ce fichier est la version SQL de ce que le module cree tout seul au
-- demarrage (ColumnLabelStore.ensureTables, pilote par
-- ColumnLabelRules.createTableStatements) :
--
--   * PROJECT_COLUMN_LABEL : une ligne par libelle choisi par la personne qui a
--     le plus de droits. La cle est (TABLE_NAME, COLUMN_NAME) ; TABLE_NAME = '*'
--     signifie « cette colonne, dans toutes les tables ».
--   * PROJECT_SETTINGS : le mode d'application (AUTO / MAPPING / OFF).
--
-- Il sert a trois choses :
--   1. documenter exactement le DDL execute par le module ;
--   2. reparer une base a la main, sans attendre un redemarrage du client ;
--   3. etre compare, par ColumnLabelRulesTest, aux instructions Java, afin
--      qu'aucune table ne soit oubliee d'un cote ou de l'autre.
--
-- Utilisation :
--   sed 's/__SCHEMA__/OpenConcerto42/g' tests/sql/migration-colonnes.sql \
--     | psql -v ON_ERROR_STOP=1 -d OpenConcerto
--
-- =====================================================================

create table if not exists "__SCHEMA__"."PROJECT_SETTINGS" (
    "KEY" varchar(128) not null primary key,
    "VALUE" varchar(1024),
    "DATE" timestamp,
    "ID_USER" integer
);

create table if not exists "__SCHEMA__"."PROJECT_COLUMN_LABEL" (
    "ID" serial primary key,
    "TABLE_NAME" varchar(64) not null,
    "COLUMN_NAME" varchar(64) not null,
    "LABEL" varchar(128) not null,
    "DATE" timestamp,
    "ID_USER" integer
);

-- Un seul libelle par (table, colonne) : c'est ce qui garantit que deux postes
-- ne peuvent pas enregistrer deux libelles differents pour la meme colonne.
create unique index if not exists "PROJECT_COLUMN_LABEL_UNQ"
    on "__SCHEMA__"."PROJECT_COLUMN_LABEL" ("TABLE_NAME", "COLUMN_NAME");

-- Le mode par defaut : suppression du prefixe ID_ dans toutes les listes.
insert into "__SCHEMA__"."PROJECT_SETTINGS" ("KEY", "VALUE", "DATE")
values ('column.label.mode', 'AUTO', now())
on conflict ("KEY") do nothing;

-- ---------------------------------------------------------------------
-- Requete de lecture des droits (qui a le plus de droits dans la base).
--
-- La ligne « -- query: roleRights » et le bloc qui suit sont lus par
-- ColumnLabelRulesTest : ils doivent rester identiques a
-- ColumnLabelRules.roleRightsQuery(). Ne pas modifier l'un sans l'autre.
-- ---------------------------------------------------------------------
-- query: roleRights
select u."ID" as "ID_USER", coalesce(u."NOM", u."LOGIN", '') as "NOM", (case when u."SUPERUSER" then 1 else 0 end) as "SUPERUSER", (case when u."ADMIN" then 1 else 0 end) as "ADMIN", (select count(*) from "__SCHEMA__"."USER_RIGHT" r where r."ID_USER_COMMON" = u."ID" and (r."HAVE_RIGHT" is null or r."HAVE_RIGHT")) as "DROITS" from "__SCHEMA__"."USER_COMMON" u where (u."IS_ACTIVE" is null or u."IS_ACTIVE") order by 3 desc, 4 desc, 5 desc, 1
-- query: end
