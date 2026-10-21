# Message court sans code (version prose)

> À envoyer tel quel au père : aucune commande, aucune requête SQL — uniquement
> l'explication du problème et de la solution.

---

Bonjour,

Le bug du transfert des commandes fournisseurs vers la saisie achat vient de la base
de production, pas du client et pas des droits.

En production, il manque une colonne sur la table des lignes de facture fournisseur :
celle qui relie une ligne de facture à la ligne de commande d'origine. La clé
étrangère et l'index qui l'accompagnent sont eux aussi absents. Cette colonne existe
dans tout le reste de l'application et dans les deux autres jeux de données que nous
avons testés : la structure de la base de production est simplement incomplète. C'est
précisément ce qui déclenche l'erreur au moment du transfert.

La correction est légère : ajouter cette colonne (un simple numéro, avec une valeur
par défaut) dans les deux schémas de la base de production, puis recréer la clé
étrangère et l'index correspondants. L'opération est sans risque, ne touche à aucune
donnée et peut être rejouée sans effet si elle est répétée. Une sauvegarde de la base
avant l'opération reste souhaitable.

Une fois la correction appliquée, le test consiste à reprendre une commande
fournisseur, à demander son transfert vers la saisie achat et à enregistrer : la
facture se crée alors normalement, comme avant.

Si tu préfères, je peux te fournir le script tout prêt à exécuter, avec la
sauvegarde et la vérification incluses.

Merci de me confirmer une fois que c'est fait, je ferai le test de mon côté.

Merci.
