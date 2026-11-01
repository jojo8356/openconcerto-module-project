-- =====================================================================
-- Correctif : OpenConcerto ne démarre plus après une table de libellés vide
--
-- Erreur affichée (deux fenêtres successives) :
--   Impossible d'accéder aux préférences
--   Erreur de connexion / Constructor failed
--   Caused by: IllegalStateException: No preferences for DBRoot SQLSchema OpenConcerto42
--
-- Et, dans le journal du client, la VRAIE cause :
--   java.lang.IllegalStateException: /PROJECT_COLUMN_LABEL/ is empty,
--                                     can not infer UNDEFINED_ID
--     at org.openconcerto.sql.model.SQLTable.findMinID(SQLTable.java:603)
--     at org.openconcerto.sql.replication.MemoryRep.replicateStruct(MemoryRep.java:334)
--     at org.openconcerto.sql.preferences.SQLPreferences.startMemCached(...)
--
-- Pourquoi : OpenConcerto a besoin, pour chaque table dont la clé primaire est
-- numérique, d'un « identifiant non défini ». Quand la politique est « min »
-- (propriété fwk_sql.debug.undefined_id, ou métadonnée « undefined ID policy »
-- du schéma), il exécute select min("ID") sur la table. Si la table est VIDE,
-- min() vaut NULL et le calcul échoue — ce qui interrompt le chargement des
-- préférences, puis la construction des éléments, puis la connexion.
--
-- La table PROJECT_COLUMN_LABEL du module était vidée à chaque
-- enregistrement de libellés (« delete from ... » puis insertions) : dès qu'il
-- n'y avait plus aucune règle, la table restait vide et le client suivant ne
-- pouvait plus démarrer.
--
-- Ce correctif ajoute une ligne sentinelle (noms vides, jamais lue comme une
-- règle). Le module est corrigé pour la conserver : cette situation ne doit
-- plus revenir.
--
-- Idempotent : peut être relancé sans effet.
-- Usage :
--   docker exec -i $C sh -c 'psql -U "$POSTGRES_USER" -d dump1009' \
--       < sql/fix-project-column-label-undefined-row.sql
-- =====================================================================

\pset pager off

BEGIN;

SET LOCAL search_path TO "OpenConcerto42";

DO $$
DECLARE
    n bigint;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema = 'OpenConcerto42'
                      AND table_name = 'PROJECT_COLUMN_LABEL') THEN
        RAISE NOTICE 'PROJECT_COLUMN_LABEL absente : ce n''est pas la cause de ce plantage';
    ELSE
        EXECUTE 'SELECT count(*) FROM "OpenConcerto42"."PROJECT_COLUMN_LABEL"' INTO n;
        RAISE NOTICE 'PROJECT_COLUMN_LABEL : % ligne(s) avant correctif', n;
        INSERT INTO "OpenConcerto42"."PROJECT_COLUMN_LABEL" ("TABLE_NAME", "COLUMN_NAME", "LABEL")
        SELECT '', '', ''
        WHERE NOT EXISTS (SELECT 1 FROM "OpenConcerto42"."PROJECT_COLUMN_LABEL");
        EXECUTE 'SELECT count(*) FROM "OpenConcerto42"."PROJECT_COLUMN_LABEL"' INTO n;
        RAISE NOTICE 'PROJECT_COLUMN_LABEL : % ligne(s) après correctif', n;
    END IF;
END $$;

COMMIT;

-- Vérification 1 : la table n'est plus vide, et min("ID") est calculable —
-- c'est exactement ce qu'OpenConcerto fait au démarrage.
SELECT count(*) AS lignes,
       min("ID") AS min_id,
       count(*) FILTER (WHERE "TABLE_NAME" = '' AND "COLUMN_NAME" = '') AS lignes_sentinelles,
       count(*) FILTER (WHERE NOT ("TABLE_NAME" = '' AND "COLUMN_NAME" = '')) AS regles_reelles
FROM "OpenConcerto42"."PROJECT_COLUMN_LABEL";

-- Vérification 2 : plus aucune table à clé numérique vide dans le schéma.
-- Ce sont celles qui empêchent le client de démarrer ; il ne doit plus en
-- rester aucune.
DO $$
DECLARE
    t record;
    n bigint;
    restantes int := 0;
BEGIN
    FOR t IN
        SELECT c.relname AS nom
          FROM pg_index i
          JOIN pg_class c     ON c.oid = i.indrelid
          JOIN pg_namespace s ON s.oid = c.relnamespace
          JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = (i.indkey)[0]
          JOIN pg_type ty     ON ty.oid = a.atttypid
         WHERE s.nspname = 'OpenConcerto42'
           AND i.indisprimary
           AND array_length(i.indkey::int[], 1) = 1
           AND ty.typname IN ('int2', 'int4', 'int8', 'numeric')
    LOOP
        EXECUTE format('SELECT count(*) FROM %I.%I', 'OpenConcerto42', t.nom) INTO n;
        IF n = 0 THEN
            restantes := restantes + 1;
            RAISE NOTICE 'TOUJOURS VIDE (bloquant au démarrage) : %', t.nom;
        END IF;
    END LOOP;
    IF restantes = 0 THEN
        RAISE NOTICE 'OK : plus aucune table vide à clé numérique';
    END IF;
END $$;

\echo ''
\echo 'Étape suivante : relancer le client OpenConcerto. Il doit se connecter.'
\echo 'Si une autre table vide est signalée ci-dessus : ne pas la remplir à la'
\echo 'main, m''envoyer la liste — ce sont des tables du coeur, pas du module.'
