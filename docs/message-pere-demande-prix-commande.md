# Réponse à ton père — transfert « demande de prix » → « commande fournisseur »

> Version prose, à envoyer telle quelle. Aucun code, aucune commande, aucun nom de fichier.

---

Bonjour,

Réponse courte : **non, ce n'est compliqué, et c'est fait.**

Ce que tu décrivais existe déjà dans OpenConcerto pour les demandes d'achat, et
on vient de le porter tel quel sur les demandes de prix. Le principe est
identique : tu arrives dans l'onglet « Demandes de prix », tu sélectionnes une
demande, et un bouton « Transfert en commande fournisseur » apparaît dans la
barre d'outils. Comme sur l'onglet « Demande d'achat », le bouton reste grisé
quand il n'y a rien à transférer : il faut d'abord qu'une demande existe et
qu'elle soit sélectionnée.

**Ce que fait le transfert, concrètement.** La commande fournisseur s'ouvre
toute seule, pré-remplie : on y retrouve les lignes de la demande de prix, avec
la désignation et la quantité. Il ne reste donc qu'une chose à faire, exactement
ce que tu disais : corriger le prix avec celui que le fournisseur t'a
réellement communiqué. Les totaux sont recalculés par le logiciel à partir des
lignes, on ne les saisit pas. Une fois enregistrée, c'est une vraie commande :
elle apparaît dans l'onglet « Commandes fournisseurs », elle compte dans le
bilan de l'affaire et dans les « à réceptionner », et elle reste rattachée à la
demande de prix dont elle est issue.

Petit point utile : le prix qui arrive dans la commande est celui qui était
renseigné dans la demande de prix. C'est une base de travail, pas un prix
figé — tu le remplaces par le prix du fournisseur, et c'est tout.

**Sur ta question sur les petites tables techniques « TR_… »** — c'est
justement le point rassurant : il n'y a **rien à créer**. OpenConcerto possède
un mécanisme standard de transfert qui conserve le lien entre le document
d'origine et le document créé ; il gère lui-même sa petite table technique, et
il l'a **créée automatiquement** à l'installation du module. J'ai vérifié
après coup dans la base : la table existe, avec son lien vers la demande de prix
et son lien vers la commande. Aucune requête à passer, aucune table à créer à
la main, aucun risque pour les données. C'est exactement ce qui se passe
déjà pour le transfert demande d'achat → commande fournisseur.

**Deux précautions**, pour que ça ne surprenne pas :

- il faut que le fournisseur soit connu sur la demande de prix au moment de la
  transformation ; si une demande de prix a été adressée à plusieurs
  fournisseurs, on fait une commande par fournisseur (le bouton travaille sur
  une demande à la fois) ;
- la commande créée est une commande réelle : elle compte dès le départ dans le
  bilan. Si tu préfères que la demande de prix reste ouverte jusqu'à la
  réception des prix, c'est le comportement actuel — dis-moi si tu préfères
  qu'elle se cloture automatiquement une fois la commande enregistrée.

Pour l'installer, c'est la mise à jour habituelle du module « project » dans
le client (menu d'administration), puis un redémarrage du client.

Un test simple quand tu l'as sous la main : ouvre une affaire, onglet
« Demandes de prix », sélectionne une demande, clique sur « Transfert en
commande fournisseur », vérifie que les lignes sont bien recopiées, saisis le
prix du fournisseur et enregistre.

Je reste à ta disposition pour ajuster le comportement, notamment sur la
clôture automatique de la demande de prix.

Bonne journée,
