# Message court pour le père — transfert « demande de prix » → « commande fournisseur »

> Version prose, à envoyer telle quelle. Aucun code, aucune commande.

---

Bonjour,

J'ai ajouté dans le module « project » une nouvelle possibilite, en discussion
tout a l'heure : transformer une **demande de prix** directement en **commande
fournisseur**.

Aujourd'hui, dans l'onglet « Demandes de prix » de l'historique des affaires, on
pouvait consulter les demandes, mais pas les transformer. Maintenant, quand une
demande de prix est selectionnee, un bouton « Transfert en commande fournisseur »
apparait dans la barre d'outils.

Le principe est celui que tu decrivais : la commande s'ouvre avec les lignes
de la demande de prix deja recopiees (designation et quantite), et le prix
repris de la demande de prix n'est qu'une base : il suffit de le corriger avec
le prix que le fournisseur t'a reellement communique avant d'enregistrer. La
commande est donc une vraie commande, visible dans l'onglet « Commandes
fournisseurs » et dans le bilan, et elle reste rattachee a la demande de prix
d'origine.

Point technique, puisque tu posais la question : il n'y a **rien à faire à la
main dans la base**. OpenConcerto possede deja un mecanisme standard de
transfert qui conserve le lien entre le document d'origine et le document
cree ; il gere lui-meme la petite table technique associee, et la cree
automatiquement a l'installation du module. Aucune table a creer, aucune
requete SQL a passer, aucun risque pour les donnees.

Deux precautions :

- comme pour toute commande fournisseur, il faut que le fournisseur soit connu
  au moment de la transformation ; si une demande de prix est adressee a
  plusieurs fournisseurs, il faut faire une commande par fournisseur (le
  bouton le permet sur une demande a la fois) ;
- la commande creee est une commande reelle : elle compte des le depart dans le
  bilan et dans les « a receptionner ». C'est a toi de voir si tu preferes
  garder la demande de prix ouverte jusqu'a la reception des prix.

Pour disposer de la possibilite, il suffit d'installer la nouvelle version du
module « project » dans le client, puis de redemarrer le client. L'installation
se fait par le menu d'administration du client (mise a jour des modules), comme
d'habitude.

Des que tu l'as sous la main, un test simple : ouvrir une affaire, onglet
« Demandes de prix », selectionner une demande, cliquer sur « Transfert en
commande fournisseur », verifier que les lignes sont bien recopiees, saisir un
prix et enregistrer.

Je reste a ta disposition pour l'ajuster, notamment si tu Prefieres que la
demande de prix soit automatiquement close une fois la commande enregistree.

Merci.
