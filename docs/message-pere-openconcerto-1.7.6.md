# OpenConcerto 1.7.6 — le transfert « commande fournisseur → facture » ne fonctionne pas

> Message prêt à envoyer. Contexte technique vérifié sur le dump de production
> `OC-v1.7.6-Noon_Dump_2026-10-09.dumpsql` (archive `pg_dump -Fc`, 7085 entrées,
> 461 tables) et sur le code source OpenConcerto 1.7.6.

---

Bonjour Papa,

J'ai terminé l'analyse du problème OpenConcerto. Ce n'est **ni un problème de droits,
ni un problème de données, ni un bug du client** : c'est **une colonne manquante dans
la base de production**. Voici le détail et le correctif.

## 1. Le symptôme

Dans OpenConcerto 1.7.6, quand on veut transformer une commande fournisseur en facture :

`Gestion → Commandes fournisseurs → clic droit sur une ligne → « Transfert vers saisie achat »`

le client s'arrête sur une erreur :

```
IllegalArgumentException: ID_COMMANDE_ELEMENT is not in table /FACTURE_FOURNISSEUR_ELEMENT/
```

La saisie d'achat s'ouvre bien, mais l'enregistrement échoue et **aucune facture
fournisseur ne peut être créée à partir d'une commande**.

Point important : ce n'est **pas propre à Gisèle**. Avec cette base, le blocage est
identique pour tout le monde (Yves, l'administrateur, Gisèle) — c'est la base qui est
incomplète, pas un compte utilisateur.

## 2. La cause exacte

Dans OpenConcerto, les lignes d'une facture fournisseur sont stockées dans la table
`FACTURE_FOURNISSEUR_ELEMENT`. Le client 1.7.6 utilise une colonne
`ID_COMMANDE_ELEMENT` dans cette table : elle mémorise **de quelle ligne de commande
fournisseur vient la ligne de facture** (c'est elle qui rend l'article et le prix
non modifiables sur une facture issue d'une commande, et qui permet de suivre
commande → facture).

**Cette colonne n'existe pas dans la base de production.**

Schéma par schéma (constaté sur le dump du 09/10/2026) :

| Schéma | Table | `ID_COMMANDE_ELEMENT` |
|---|---|---|
| `Common` | (socle partagé) | sans objet |
| `Default` (schéma modèle de la société 1) | `FACTURE_FOURNISSEUR_ELEMENT` | **ABSENTE** |
| `OpenConcerto42` (KINETIC-THERM) | `FACTURE_FOURNISSEUR_ELEMENT` | **ABSENTE** |

Et, à l'inverse, la **même colonne existe bien** sur `BON_RECEPTION_ELEMENT`
(lignes des bons de réception) dans les deux schémas : les mises à jour de structure
d'OpenConcerto 1.5 ont donc été faites, mais **la table des lignes de facture
fournisseur a été oubliée**.

C'est un défaut connu d'OpenConcerto 1.7.6 : à l'installation, le programme crée
`FACTURE_FOURNISSEUR_ELEMENT` **sans** cette colonne (l'updater 1.5 ne l'ajoute
que pour les bons de réception). Et comme toute nouvelle société est créée à partir
du schéma `Default`, **toutes** les sociétés créées depuis — dont KINETIC-THERM —
en sont dépourvues.

Preuve chiffrée : dans le diff entre la structure de la production et la structure
corrigée, il ne manque que **4 éléments** :

- la colonne `ID_COMMANDE_ELEMENT` sur `Default.FACTURE_FOURNISSEUR_ELEMENT`
- sa contrainte de clé étrangère vers `COMMANDE_ELEMENT`
- son index
- et les 3 mêmes éléments dans le schéma `OpenConcerto42`

Aucune autre différence de structure. Les 461 tables, les index et les contraintes sont
identiques. **Les données sont intactes.**

## 3. Le correctif (à appliquer sur la base de production)

### 3.1 Sauvegarde avant toute chose

```bash
pg_dump -h ADRESSE -U UTILISATEUR -d BASE -Fc -f sauvegarde-avant-correctif-$(date +%F).dump
```

### 3.2 Ajout de la colonne manquante

À exécuter sur la base de production, **une fois par schéma**.
Le script est idempotent : il peut être rejoué sans risque.

```sql
-- ===== Schéma Default =====
BEGIN;
SET LOCAL search_path TO "Default";

ALTER TABLE "FACTURE_FOURNISSEUR_ELEMENT"
    ADD COLUMN IF NOT EXISTS "ID_COMMANDE_ELEMENT" integer DEFAULT 1;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = 'Default'
          AND t.relname = 'FACTURE_FOURNISSEUR_ELEMENT'
          AND c.conname = 'FACTURE_FOURNISSEUR_ELEMENT_ID_COMMANDE_ELEMENT_fkey'
    ) THEN
        ALTER TABLE "FACTURE_FOURNISSEUR_ELEMENT"
            ADD CONSTRAINT "FACTURE_FOURNISSEUR_ELEMENT_ID_COMMANDE_ELEMENT_fkey"
            FOREIGN KEY ("ID_COMMANDE_ELEMENT") REFERENCES "COMMANDE_ELEMENT" ("ID");
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS "FACTURE_FOURNISSEUR_ELEMENT_ID_COMMANDE_ELEMENT_fki"
    ON "FACTURE_FOURNISSEUR_ELEMENT" ("ID_COMMANDE_ELEMENT");
COMMIT;


-- ===== Schéma OpenConcerto42 (KINETIC-THERM) =====
BEGIN;
SET LOCAL search_path TO "OpenConcerto42";

ALTER TABLE "FACTURE_FOURNISSEUR_ELEMENT"
    ADD COLUMN IF NOT EXISTS "ID_COMMANDE_ELEMENT" integer DEFAULT 1;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = 'OpenConcerto42'
          AND t.relname = 'FACTURE_FOURNISSEUR_ELEMENT'
          AND c.conname = 'FACTURE_FOURNISSEUR_ELEMENT_ID_COMMANDE_ELEMENT_fkey'
    ) THEN
        ALTER TABLE "FACTURE_FOURNISSEUR_ELEMENT"
            ADD CONSTRAINT "FACTURE_FOURNISSEUR_ELEMENT_ID_COMMANDE_ELEMENT_fkey"
            FOREIGN KEY ("ID_COMMANDE_ELEMENT") REFERENCES "COMMANDE_ELEMENT" ("ID");
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS "FACTURE_FOURNISSEUR_ELEMENT_ID_COMMANDE_ELEMENT_fki"
    ON "FACTURE_FOURNISSEUR_ELEMENT" ("ID_COMMANDE_ELEMENT");
COMMIT;
```

En pratique (sur le serveur) :

```bash
psql -h ADRESSE -U UTILISATEUR -d BASE -v ON_ERROR_STOP=1 -f correctif-id-commande-element.sql
```

> Si la base a d'autres schémas que `Default` et `OpenConcerto42`, il faut répéter le
> bloc pour chacun (le schéma `Default` est le plus important : c'est lui qui sert
> de modèle aux sociétés futures).

### 3.3 Vérification

La requête doit maintenant renvoyer **2 lignes** (`Default` et `OpenConcerto42`) :

```sql
SELECT table_schema, column_name, data_type, column_default
FROM information_schema.columns
WHERE table_name = 'FACTURE_FOURNISSEUR_ELEMENT'
  AND column_name = 'ID_COMMANDE_ELEMENT';
```

Et la contrainte de clé étrangère doit exister dans les deux schémas :

```sql
SELECT n.nspname AS schema, conname
FROM pg_constraint c
JOIN pg_class t ON t.oid = c.conrelid
JOIN pg_namespace n ON n.oid = t.relnamespace
WHERE conname = 'FACTURE_FOURNISSEUR_ELEMENT_ID_COMMANDE_ELEMENT_fkey';
```

## 4. Contrôle dans l'interface (après le correctif)

1. Ouvrir OpenConcerto 1.7.6, se connecter avec le compte concerné.
2. `Gestion → Commandes fournisseurs` (société KINETIC-THERM).
3. Clic droit sur **une seule** ligne de commande → **« Transfert vers saisie achat »**.
4. Le formulaire « Achat fournisseur » s'ouvre pré-rempli (fournisseur, n° de commande,
   montants, lignes d'articles). L'article et le prix des lignes doivent apparaître
   **non modifiables** (c'est normal : ils viennent de la commande).
5. **Enregistrer** → la facture est créée, et cette fois **sans erreur**.

Vérification en base de la ligne créée :

```sql
SELECT f."NUMERO", f."DATE", fe."ID_COMMANDE_ELEMENT"
FROM "OpenConcerto42"."FACTURE_FOURNISSEUR" f
JOIN "OpenConcerto42"."FACTURE_FOURNISSEUR_ELEMENT" fe
  ON fe."ID_FACTURE_FOURNISSEUR" = f."ID"
ORDER BY f."ID" DESC
LIMIT 10;
```

La colonne `ID_COMMANDE_ELEMENT` doit contenir l'identifiant de la ligne de commande
d'origine (et non `1`, qui est la valeur « non défini » d'OpenConcerto).

## 5. Ce qu'il ne faut surtout pas faire

- **Ne pas recréer la base** : les données sont saines, seule la structure est incomplète.
- **Ne pas modifier les droits des utilisateurs** : l'audit des droits a été refait avec
  le moteur exact d'OpenConcerto 1.7 ; les droits d'écriture sur `COMMANDE`,
  `COMMANDE_ELEMENT`, `FACTURE_FOURNISSEUR` et `FACTURE_FOURNISSEUR_ELEMENT` sont
  corrects pour tous les comptes. Il n'y a rien à granting ni à retirer.
- **Ne pas faire de `DROP`/`TRUNCATE`** : la commande ci-dessus est un `ALTER TABLE`
  qui ne touche à aucune donnée existante.

## 6. Points secondaires à voir plus tard (non bloquants)

1. **Autres colonnes manquantes** : un audit complet de la structure a été fait. La
   colonne `ID_COMMANDE_ELEMENT` était la seule bloquante, mais les tables de lignes
   d'achat peuvent aussi manquer des colonnes attendues par l'interface
   (`QTE_ACHAT`, `QTE_UNITAIRE`, `ID_UNITE_VENTE`, `ID_ARTICLE`, `PA_DEVISE`,
   `ID_DEVISE`, `PA_DEVISE_T`, `DESCRIPTIF`). Un script d'audit + un correctif
   idempotent sont prêts ; ils ne sont pas nécessaires pour le transfert, mais
   permettent d'aligner la base sur la structure attendue par le client.
2. **Module « supplychain invoice importer »** : dans le client, ce module est
   signalé « non disponible ». Il n'est pas nécessaire pour le transfert corrigé,
   mais il peut l'être pour d'autres scénarios d'import de factures.
3. **Sauvegardes** : le dump du 09/10/2026 est sain et restaurable ; il sera
   intéressant de le re-faire après le correctif, pour disposer d'une référence
   « structure à jour ».

---

Dis-moi si tu veux que je passe sur le serveur pour appliquer le correctif, ou que je
te prépare le fichier `.sql` prêt à lancer et la sauvegarde à faire avant.
