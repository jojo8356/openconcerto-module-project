# Aide > Diagnostic affaire — pourquoi l'affaire ne s'affiche pas

Un clic, un rapport, aucune modification de données. Le diagnostic répond à la
question « pourquoi le champ **Affaire** est-il vide ou grisé **pour cet
utilisateur** ? » — sans SQL, depuis sa propre session.

## Où le trouver

Menu **Aide → Diagnostic affaire**. Le rapport s'affiche dans une fenêtre (texte
sélectionnable) et il est aussi écrit dans le journal du client, préfixé
`[module project] diagnostic affaire`.

## Ce qu'il contient

```
diagnostic affaire — Thu Oct 29 11:02:13 CET 2026
utilisateur : REBSTOCK Gisele (ID 18)
superutilisateur : NON

droits sur les tables (lecture / modification) :
  AFFAIRE                : lecture oui, modification oui, 383 ligne(s)
  COMMANDE               : lecture oui, modification oui, 512 ligne(s)
  FACTURE_FOURNISSEUR    : lecture oui, modification oui, 118 ligne(s)
  ...

menu déroulant des affaires :
  entrées proposées : 383
  entrées sans texte : 11 (ID 375, 376, 377, 378, 379) — elles s'affichent comme des lignes vides
  trois premières entrées : 12167 SANOFI EUROPA FRANCE, 12086, 12001
```

## Comment lire le résultat

| Ce qu'on lit | Diagnostic | Ce qu'il faut faire |
|---|---|---|
| `lecture NON` sur `AFFAIRE` | les droits bloquent l'affichage : le combo se remplit à vide | donner le droit de lecture sur `AFFAIRE` (ou `TABLE_ALL_RIGHTS`) au compte |
| `entrées proposées : 0` | le menu déroulant est vide → champ grisé | droits, ou table `AFFAIRE` vide |
| `entrées proposées : 383` mais l'affaire du document n'y est pas | le filtre de la requête exclut cette ligne | vérifier l'état de l'affaire (`DOSSIER_CLOS`) et les colonnes de filtre |
| `entrées sans texte : 11` | des affaires sans état ni nom s'affichent comme des lignes vides | compléter les affaires, ou utiliser le libellé de repli |
| tout est `oui` et le compte des entrées est correct | le problème est ailleurs (document, transfert, rafraîchissement) | me transmettre le rapport |

## Pourquoi les droits peuvent surprendre

Le cœur applique deux règles peu visibles :

1. **héritage** : si un compte n'a aucune ligne pour un code de droit, le cœur
   interroge le compte « Indéfini » (ID 1) — c'est ainsi qu'un compte sans
   `TABLE_ALL_RIGHTS` peut quand même lire les tables ;
2. **priorité** : pour un couple code/objet, c'est la ligne d'**ID le plus bas**
   qui l'emporte (`UserRightsManager.expand`), donc une interdiction ancienne
   peut masquer un droit accordé plus tard.

Le diagnostic affiche le résultat **de ces règles**, pas les lignes brutes : ce
que vous voyez est ce que le cœur décide réellement.

## Limites

- Il lit la base : l'affichage prend une seconde environ.
- Il ne corrige rien : c'est volontaire, un diagnostic ne doit pas modifier les
  droits ni les affaires.

## Vérifications automatiques

Le calcul des droits et l'héritage sont couverts côté base par
`sql/diagnostic-droits-affaire.sql` (mêmes règles, en SQL, utile pour comparer
deux comptes). Le module lui-même ne fait ici que de la lecture et de la mise en
forme.
