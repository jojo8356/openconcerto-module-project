-- =====================================================================
-- Diagnostic (LECTURE SEULE) : « No preferences for DBRoot SQLSchema OpenConcerto42 »
--
-- Erreur affichée au démarrage du client :
--   Erreur de connexion / Constructor failed
--   Caused by: IllegalStateException: No preferences for DBRoot SQLSchema OpenConcerto42
--     at SQLPreferences.getMemCached(:148)
--     at ReferenceArticleSQLElement.<init>(:168)
--     at ComptaPropsConfiguration.setSocieteDirectory(:949)
--
-- Pourquoi : au démarrage, OpenConcerto charge les préférences de la société
-- (tables PREF_NODE et PREF_VALUE du schéma OpenConcerto42) :
--
--   SQLPreferences.getPrefTable(rootSociete)    cree les tables si absentes
--   SQLPreferences.startMemCached(rootSociete)  charge les preferences en memoire
--
-- Ces deux appels sont dans un try/catch qui affiche seulement
-- « Impossible d'accéder aux préférences » et continue. Le cache reste vide,
-- et le premier élément qui lit une préférence (ReferenceArticleSQLElement)
-- echoue alors avec « No preferences for DBRoot ».
--
-- Ce script ne modifie rien : il photographie l'état de la base pour savoir
-- POURQUOI ce chargement a échoué.
--
-- Usage :
--   docker exec -i $C sh -c 'psql -U "$POSTGRES_USER" -d dump1009' \
--       < sql/diagnostic-connexion-preferences.sql
-- =====================================================================

\pset pager off
\set ON_ERROR_STOP off

\echo ''
\echo '=== 0. Base, rôle, serveur ==='
SELECT current_database() AS base,
       current_user     AS role_utilise,
       current_setting('server_version') AS version_pg,
       (SELECT r.rolname FROM pg_roles r WHERE r.rolsuper AND r.rolname = current_user) AS superutilisateur;

\echo ''
\echo '=== 1. Schéma OpenConcerto42 ==='
SELECT nspname                                   AS schema,
       pg_get_userbyid(nspowner)                 AS proprietaire,
       has_schema_privilege(current_user, nspname, 'USAGE')  AS peut_utiliser,
       has_schema_privilege(current_user, nspname, 'CREATE') AS peut_creer
FROM pg_namespace
WHERE nspname = 'OpenConcerto42';

\echo ''
\echo '=== 2. Droits du rôle du client (openconcerto) ==='
SELECT r.rolname                                    AS role_client,
       has_schema_privilege(r.rolname, 'OpenConcerto42', 'USAGE')  AS peut_utiliser,
       has_schema_privilege(r.rolname, 'OpenConcerto42', 'CREATE') AS peut_creer
FROM pg_roles r
WHERE r.rolname IN ('openconcerto', 'postgres')
ORDER BY r.rolname;

\echo ''
\echo '=== 3. Tables de préférences attendues par le client ==='
SELECT t.nom,
       EXISTS (SELECT 1 FROM information_schema.tables i
                WHERE i.table_schema = 'OpenConcerto42' AND i.table_name = t.nom) AS presente,
       (SELECT count(*) FROM information_schema.columns c
         WHERE c.table_schema = 'OpenConcerto42' AND c.table_name = t.nom)      AS nb_colonnes
FROM (SELECT 'PREF_NODE' AS nom UNION ALL SELECT 'PREF_VALUE') t;

\echo ''
\echo '=== 4. Contenu des tables de préférences ==='
DO $$
DECLARE
    n bigint;
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables
                WHERE table_schema = 'OpenConcerto42' AND table_name = 'PREF_NODE') THEN
        EXECUTE 'SELECT count(*) FROM "OpenConcerto42"."PREF_NODE"' INTO n;
        RAISE NOTICE 'PREF_NODE  : % ligne(s)', n;
    ELSE
        RAISE NOTICE 'PREF_NODE  : ABSENTE';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables
                WHERE table_schema = 'OpenConcerto42' AND table_name = 'PREF_VALUE') THEN
        EXECUTE 'SELECT count(*) FROM "OpenConcerto42"."PREF_VALUE"' INTO n;
        RAISE NOTICE 'PREF_VALUE : % ligne(s)', n;
    ELSE
        RAISE NOTICE 'PREF_VALUE : ABSENTE';
    END IF;
END $$;

\echo ''
\echo '=== 5. Séquences PREF_* (une création interrompue les laisse orphelines) ==='
SELECT sequencename AS sequence
FROM pg_sequences
WHERE schemaname = 'OpenConcerto42' AND sequencename LIKE 'PREF%'
ORDER BY 1;

\echo ''
\echo '=== 6. La base ressemble-t-elle à une base OpenConcerto complète ? ==='
SELECT count(*) FILTER (WHERE table_name IN ('SOCIETE', 'SOCIETE_COMMON', 'ARTICLE',
                                             'FACTURE_FOURNISSEUR', 'COMMANDE',
                                             'FACTURE_FOURNISSEUR_ELEMENT')) AS tables_cles_presentes,
       count(*)                                                            AS tables_du_schema
FROM information_schema.tables
WHERE table_schema = 'OpenConcerto42';

\echo ''
\echo '=== 7. Sociétés déclarées ==='
DO $$
DECLARE
    n bigint;
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables
                WHERE table_schema = 'OpenConcerto42' AND table_name = 'SOCIETE_COMMON') THEN
        EXECUTE 'SELECT count(*) FROM "OpenConcerto42"."SOCIETE_COMMON"' INTO n;
        RAISE NOTICE 'SOCIETE_COMMON : % ligne(s)', n;
    ELSE
        RAISE NOTICE 'SOCIETE_COMMON : ABSENTE';
    END IF;
END $$;

\echo ''
\echo '=== 8. Le correctif ID_COMMANDE_ELEMENT est-il appliqué ? ==='
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_schema = 'OpenConcerto42'
  AND table_name = 'FACTURE_FOURNISSEUR_ELEMENT'
  AND column_name = 'ID_COMMANDE_ELEMENT';

\echo ''
\echo '=== Fin du diagnostic ==='
