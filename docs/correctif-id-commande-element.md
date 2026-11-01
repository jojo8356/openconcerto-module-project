# Corriger « ID_COMMANDE_ELEMENT is not in table /FACTURE_FOURNISSEUR_ELEMENT/ »

Erreur affichée au moment du **transfert d'une commande fournisseur vers une
facture fournisseur** :

```
CommandeSQLElement$3$1.done
  FactureFournisseurSQLComponent.loadQuantity
    java.lang.IllegalArgumentException: ID_COMMANDE_ELEMENT is not in table /FACTURE_FOURNISSEUR_ELEMENT/
```

## Pourquoi

OpenConcerto 1.7.6 écrit, pendant le transfert, un lien entre **chaque ligne de
facture** et **la ligne de commande** dont elle vient. Il enregistre ce lien dans
la colonne `FACTURE_FOURNISSEUR_ELEMENT.ID_COMMANDE_ELEMENT`.

Sur une base qui a été créée (ou restaurée) sans cette colonne, l'écriture
échoue et **le transfert est abandonné en entier** : la facture est créée, mais
aucun lien vers la commande n'est enregistré. C'est pour cette raison qu'une
facture peut afficher son affaire et **pas** son numéro de commande : ce numéro
n'est pas stocké sur la facture, il est déduit de ce lien.

Ce n'est donc pas un défaut d'affichage : c'est une colonne manquante.

## 1. Se procurer le script

Deux fichiers suffisent, et ils n'ont pas besoin du reste du dépôt. Le plus
simple, sur la machine OpenConcerto :

```sh
mkdir -p ~/oc-fix/scripts ~/oc-fix/sql && cd ~/oc-fix
B=https://raw.githubusercontent.com/jojo8356/openconcerto-module-project/arena/ff79607f-openconcerto-module-project
curl -fsS "$B/scripts/fix-facture-fournisseur-element.sh" -o scripts/fix-facture-fournisseur-element.sh
curl -fsS "$B/sql/fix-facture-fournisseur-element-id-commande-element.sql" -o sql/fix-facture-fournisseur-element-id-commande-element.sql
ls -l scripts sql
```

Si le dépôt est déjà sur la machine, travaillez directement dedans (le script
retrouve le SQL tout seul, il suffit de garder l'arborescence `scripts/` +
`sql/`).

`~/oc-fix` doit rester le dossier courant pour les commandes suivantes : le
script lit `../sql/fix-facture-fournisseur-element-id-commande-element.sql`.

## 2. Vérifier l'état de la base

Le client affiche la base indiquée dans sa configuration ; le conteneur est
celui de votre installation (`docker ps` pour le retrouver).

```sh
C=openconcerto176-db-1          # docker ps --format '{{.Names}}' pour le retrouver
grep systemRoot ~/.config/OpenConcerto/main.properties
```

Le `systemRoot=` affiché est **la base à corriger**. Le contrôle ne modifie
rien :

```sh
bash scripts/fix-facture-fournisseur-element.sh --check -D "$C" -d dump1009
```

Deux réponses possibles :

| Sortie | Code | Signification |
| --- | --- | --- |
| `colonne absente -> le transfert échouera` | 3 | il faut appliquer le correctif |
| `colonne présente -> le transfert est possible` | 0 | rien à faire ; le problème est ailleurs |

## 3. Appliquer le correctif

```sh
bash scripts/fix-facture-fournisseur-element.sh -D "$C" -d dump1009 -y
```

Le script, dans cet ordre :

1. vérifie que la base et les tables `FACTURE_FOURNISSEUR_ELEMENT` et
   `COMMANDE_ELEMENT` existent ;
2. **sauvegarde la base** dans
   `oc-update-AAAA-MM-JJ/backup_avant_fix_AAA-MM-JJ_HHMM.dumpsql` et refuse de
   continuer si la sauvegarde est vide ;
3. applique
   `sql/fix-facture-fournisseur-element-id-commande-element.sql` (transaction
   unique, idempotent) ;
4. relit la colonne (`integer|1` attendu) ;
5. produit un dump complet à jour
   `oc-update-AAAA-MM-JJ/OpenConcerto-1.7.6-a-jour_….dumpsql` avec son empreinte
   SHA-256, à transmettre à toute autre installation.

Le SQL applique exactement le fichier livré ; le script ne fait que l'entourer.
Il ajoute la colonne, la clé étrangère vers `COMMANDE_ELEMENT("ID")` (si la
table visée a une contrainte d'unicité, comme dans une base OpenConcerto
normale) et l'index `…_fki`.

Une **seconde exécution** ne fait rien et le dit :

```
La colonne est déjà là : rien à modifier (le script reste sans effet).
```

### Variante sans Docker

Si `psql` et `pg_dump` sont installés sur la machine et que la base est
joignable directement (variables `PG*` ou `~/.pgpass`), remplacez `-D "$C"` par
`-h HOTE -p PORT -U ROLE` :

```sh
bash scripts/fix-facture-fournisseur-element.sh -d dump1009 -U openconcerto -h 127.0.0.1 -p 5433 -y
```

## 4. Après le correctif

1. **Redémarrer le client OpenConcerto** : il lit le schéma de la base à
   l'ouverture ; sans redémarrage il continue de croire que la colonne n'existe
   pas.
2. Refaire le transfert de la commande fournisseur vers la facture
   fournisseur : il doit aboutir.
3. Rouvrir la facture : la ligne « N° commande » est remplie.

Les factures créées **avant** le correctif restent sans lien — c'est exact, le
transfert n'avait rien enregistré. Pour les relier, refaire le transfert depuis
la commande, ou saisir le lien à la main ; la colonne « Affaire », elle, ne
dépend pas de ce correctif.

## 5. Revenir en arrière

```sh
ls -l oc-update-*/backup_avant_fix_*.dumpsql
```

```sh
docker cp oc-update-AAAA-MM-JJ/backup_avant_fix_AAAA-MM-JJ_HHMM.dumpsql \
  "$C":/tmp/avant.dumpsql
docker exec -i "$C" sh -c 'pg_restore -U "$POSTGRES_USER" -d dump1009 --clean --if-exists /tmp/avant.dumpsql'
```

La sauvegarde est au format `pg_dump -Fc` : elle se restaure avec `pg_restore`,
jamais avec `psql`.

## 6. Ce qui est vérifié automatiquement

Le contrôle `controle-affaire-complet.sql` (section 0.4) répond sur la base :

```
id_commande_element
ABSENTE : lancer sql/fix-facture-fournisseur-element-id-commande-element.sql
```

et, après correctif, `presente : le transfert commande -> facture est possible`.

Le job CI « Correctif ID_COMMANDE_ELEMENT (script complet) » rejoue tout le
parcours sur un PostgreSQL 16 jetable, à chaque validation :
colonne absente → sauvegarde → correctif → colonne présente → relance sans
effet → écriture réelle d'un lien ligne de facture → ligne de commande, avec
rejet d'une ligne inexistante par la clé étrangère.
