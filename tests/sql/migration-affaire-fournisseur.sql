-- =====================================================================
-- Migration « affaire » des documents fournisseurs (reference SQL)
-- =====================================================================
--
-- Ce fichier est la version SQL de ce que le module fait maintenant tout
-- seul au demarrage (Module.ensureAffairColumns, pilote par
-- AffairLinkSupport.DIRECT_AFFAIR_TABLES) :
--
--   * chaque table de document rattachable a une affaire recoit la colonne
--     ID_AFFAIRE si elle ne l'a pas deja ;
--   * la contrainte de cle etrangere vers AFFAIRE est ajoutee quand elle
--     manque ;
--   * l'operation est idempotente : on peut la rejouer sans risque.
--
-- Il sert a trois choses :
--   1. documenter exactement le DDL execute par le module ;
--   2. reparer une base a la main (ou en SQL) sans attendre un redemarrage ;
--   3. etre compare, par AffairLinkSupportTest, a la liste Java afin
--      qu'aucune table ne soit oubliee d'un cote ou de l'autre.
--
-- IMPORTANT : les tables de LIGNES (COMMANDE_ELEMENT, BON_RECEPTION_ELEMENT,
-- FACTURE_FOURNISSEUR_ELEMENT, ...) ne recoivent volontairement PAS de
-- colonne ici. Elles sont rattachees a l'affaire par leur document parent
-- (voir AffairLinkSupport.PARENT_LINKS) : ajouter une colonne de ligne
-- desactiverait ce filtrage et rendrait invisibles les lignes dont l'affaire
-- de ligne est vide.
--
-- Utilisation :
--   sed 's/__SCHEMA__/OpenConcerto42/g' tests/sql/migration-affaire-fournisseur.sql \
--     | psql -v ON_ERROR_STOP=1 -d OpenConcerto
--
-- La ligne « -- table: NOM » est lue par AffairLinkSupportTest : ne pas la
-- modifier sans mettre a jour DIRECT_AFFAIR_TABLES.
-- =====================================================================

-- table: DEVIS
alter table "__SCHEMA__"."DEVIS" add column if not exists "ID_AFFAIRE" integer;
-- table: COMMANDE_CLIENT
alter table "__SCHEMA__"."COMMANDE_CLIENT" add column if not exists "ID_AFFAIRE" integer;
-- table: SAISIE_VENTE_FACTURE
alter table "__SCHEMA__"."SAISIE_VENTE_FACTURE" add column if not exists "ID_AFFAIRE" integer;
-- table: AVOIR_CLIENT
alter table "__SCHEMA__"."AVOIR_CLIENT" add column if not exists "ID_AFFAIRE" integer;
-- table: BON_DE_LIVRAISON
alter table "__SCHEMA__"."BON_DE_LIVRAISON" add column if not exists "ID_AFFAIRE" integer;
-- table: DEMANDE_PRIX
alter table "__SCHEMA__"."DEMANDE_PRIX" add column if not exists "ID_AFFAIRE" integer;
-- table: BON_RECEPTION
alter table "__SCHEMA__"."BON_RECEPTION" add column if not exists "ID_AFFAIRE" integer;
-- table: COMMANDE
alter table "__SCHEMA__"."COMMANDE" add column if not exists "ID_AFFAIRE" integer;
-- table: FACTURE_FOURNISSEUR
alter table "__SCHEMA__"."FACTURE_FOURNISSEUR" add column if not exists "ID_AFFAIRE" integer;
-- table: SAISIE_ACHAT
alter table "__SCHEMA__"."SAISIE_ACHAT" add column if not exists "ID_AFFAIRE" integer;
-- table: AVOIR_FOURNISSEUR
alter table "__SCHEMA__"."AVOIR_FOURNISSEUR" add column if not exists "ID_AFFAIRE" integer;
-- table: DEMANDE_ACHAT_ELEMENT
alter table "__SCHEMA__"."DEMANDE_ACHAT_ELEMENT" add column if not exists "ID_AFFAIRE" integer;

-- ---------------------------------------------------------------------
-- Contraintes de cle etrangere vers AFFAIRE (ajoutees si elles manquent).
-- Elles ne sont PAS indispensables au filtrage : elles protegent seulement
-- les nouvelles ecritures.
--
-- Elles sont creees "NOT VALID" a dessein. Une base de production contient
-- souvent des documents qui pointent vers une affaire supprimee (cas
-- « AFFAIRE INEXISTANTE » du rapport de lignes manquantes) : une contrainte
-- validee d'emblee echouerait, la migration serait interrompue et la colonne
-- resterait absente. C'est exactement le mode d'echec silencieux que l'audit
-- a identifie.
-- ---------------------------------------------------------------------
do $migration_affaire$
declare
    t text;
    affaire_key text;
begin
    select a.attname into affaire_key
    from pg_index i
             join pg_class c on c.oid = i.indrelid
             join pg_namespace n on n.oid = c.relnamespace
             join pg_attribute a on a.attrelid = c.oid and a.attnum = any (i.indkey)
    where n.nspname = '__SCHEMA__' and c.relname = 'AFFAIRE' and i.indisprimary
    limit 1;

    if affaire_key is null then
        raise notice 'AFFAIRE absente du schema __SCHEMA__ : migration limitee aux colonnes';
        return;
    end if;

    foreach t in array array['DEVIS', 'COMMANDE_CLIENT', 'SAISIE_VENTE_FACTURE', 'AVOIR_CLIENT', 'BON_DE_LIVRAISON',
                             'DEMANDE_PRIX', 'BON_RECEPTION', 'COMMANDE', 'FACTURE_FOURNISSEUR', 'SAISIE_ACHAT',
                             'AVOIR_FOURNISSEUR', 'DEMANDE_ACHAT_ELEMENT']
        loop
            if exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                       where n.nspname = '__SCHEMA__' and c.relname = t)
               and not exists (select 1
                               from pg_constraint cons
                                        join pg_class c on c.oid = cons.conrelid
                                        join pg_namespace n on n.oid = c.relnamespace
                                        join pg_class rc on rc.oid = cons.confrelid
                               where n.nspname = '__SCHEMA__' and c.relname = t and cons.contype = 'f'
                                 and rc.relname = 'AFFAIRE')
            then
                execute format('alter table %I.%I add constraint %I foreign key ("ID_AFFAIRE") references %I.%I (%I) not valid',
                               '__SCHEMA__', t, t || '_ID_AFFAIRE_fkey', '__SCHEMA__', 'AFFAIRE', affaire_key);
            end if;
        end loop;
end
$migration_affaire$;

-- ---------------------------------------------------------------------
-- Index : l'historique des affaires filtre sur cette colonne.
-- ---------------------------------------------------------------------
create index if not exists "DEVIS_ID_AFFAIRE_idx" on "__SCHEMA__"."DEVIS" ("ID_AFFAIRE");
create index if not exists "COMMANDE_CLIENT_ID_AFFAIRE_idx" on "__SCHEMA__"."COMMANDE_CLIENT" ("ID_AFFAIRE");
create index if not exists "SAISIE_VENTE_FACTURE_ID_AFFAIRE_idx" on "__SCHEMA__"."SAISIE_VENTE_FACTURE" ("ID_AFFAIRE");
create index if not exists "AVOIR_CLIENT_ID_AFFAIRE_idx" on "__SCHEMA__"."AVOIR_CLIENT" ("ID_AFFAIRE");
create index if not exists "BON_DE_LIVRAISON_ID_AFFAIRE_idx" on "__SCHEMA__"."BON_DE_LIVRAISON" ("ID_AFFAIRE");
create index if not exists "DEMANDE_PRIX_ID_AFFAIRE_idx" on "__SCHEMA__"."DEMANDE_PRIX" ("ID_AFFAIRE");
create index if not exists "BON_RECEPTION_ID_AFFAIRE_idx" on "__SCHEMA__"."BON_RECEPTION" ("ID_AFFAIRE");
create index if not exists "COMMANDE_ID_AFFAIRE_idx" on "__SCHEMA__"."COMMANDE" ("ID_AFFAIRE");
create index if not exists "FACTURE_FOURNISSEUR_ID_AFFAIRE_idx" on "__SCHEMA__"."FACTURE_FOURNISSEUR" ("ID_AFFAIRE");
create index if not exists "SAISIE_ACHAT_ID_AFFAIRE_idx" on "__SCHEMA__"."SAISIE_ACHAT" ("ID_AFFAIRE");
create index if not exists "AVOIR_FOURNISSEUR_ID_AFFAIRE_idx" on "__SCHEMA__"."AVOIR_FOURNISSEUR" ("ID_AFFAIRE");
create index if not exists "DEMANDE_ACHAT_ELEMENT_ID_AFFAIRE_idx" on "__SCHEMA__"."DEMANDE_ACHAT_ELEMENT" ("ID_AFFAIRE");
