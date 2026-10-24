# Message court pour le père (version condensée)

> Version « 30 secondes » du message. Le détail complet reste dans
> `docs/message-pere-openconcerto-1.7.6.md`.

---

Bonjour,

**Problème** : le transfert d'une commande fournisseur vers la saisie achat échoue
(« X is not in table /T/FACTURE_FOURNISSEUR_ELEMENT/ »).

**Cause** : dans la base de production, il manque sur la table
`FACTURE_FOURNISSEUR_ELEMENT` la colonne `ID_COMMANDE_ELEMENT` (ainsi que sa clé
étrangère et son index), dans les 2 schémas `Default` et `OpenConcerto42`.
Le reste de la structure est identique à celle qui fonctionne. Ce n'est ni un
problème de droits, ni de données.

**Avant**, une sauvegarde :

```
pg_dump -Fc -d OpenConcertoKineticTherm -f ~/sauvegarde-avant-correctif.dump
```

**Correctif** (idempotent, à passer sur la base de prod) :

```sql
BEGIN;
SET LOCAL search_path TO "Default";
ALTER TABLE "FACTURE_FOURNISSEUR_ELEMENT" ADD COLUMN IF NOT EXISTS "ID_COMMANDE_ELEMENT" integer DEFAULT 1;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace WHERE n.nspname='Default' AND t.relname='FACTURE_FOURNISSEUR_ELEMENT' AND c.conname='FACTURE_FOURNISSEUR_ELEMENT_ID_COMMANDE_ELEMENT_fkey') THEN
ALTER TABLE "FACTURE_FOURNISSEUR_ELEMENT" ADD CONSTRAINT "FACTURE_FOURNISSEUR_ELEMENT_ID_COMMANDE_ELEMENT_fkey" FOREIGN KEY ("ID_COMMANDE_ELEMENT") REFERENCES "COMMANDE_ELEMENT" ("ID"); END IF; END $$;
CREATE INDEX IF NOT EXISTS "FACTURE_FOURNISSEUR_ELEMENT_ID_COMMANDE_ELEMENT_fki" ON "FACTURE_FOURNISSEUR_ELEMENT" ("ID_COMMANDE_ELEMENT");
COMMIT;

BEGIN;
SET LOCAL search_path TO "OpenConcerto42";
ALTER TABLE "FACTURE_FOURNISSEUR_ELEMENT" ADD COLUMN IF NOT EXISTS "ID_COMMANDE_ELEMENT" integer DEFAULT 1;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace WHERE n.nspname='OpenConcerto42' AND t.relname='FACTURE_FOURNISSEUR_ELEMENT' AND c.conname='FACTURE_FOURNISSEUR_ELEMENT_ID_COMMANDE_ELEMENT_fkey') THEN
ALTER TABLE "FACTURE_FOURNISSEUR_ELEMENT" ADD CONSTRAINT "FACTURE_FOURNISSEUR_ELEMENT_ID_COMMANDE_ELEMENT_fkey" FOREIGN KEY ("ID_COMMANDE_ELEMENT") REFERENCES "COMMANDE_ELEMENT" ("ID"); END IF; END $$;
CREATE INDEX IF NOT EXISTS "FACTURE_FOURNISSEUR_ELEMENT_ID_COMMANDE_ELEMENT_fki" ON "FACTURE_FOURNISSEUR_ELEMENT" ("ID_COMMANDE_ELEMENT");
COMMIT;
```

**Vérification** (doit renvoyer 2 lignes) :

```sql
SELECT table_schema, column_name, data_type, column_default
FROM information_schema.columns
WHERE table_name='FACTURE_FOURNISSEUR_ELEMENT' AND column_name='ID_COMMANDE_ELEMENT';
```

**Test fonctionnel** : Fournisseurs → Commandes fournisseurs → une ligne →
clic droit → « Transfert vers saisie achat » → Enregistrer. Ça doit passer.

Merci.
