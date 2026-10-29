# Recette graphique — à faire avec le compte de Gisèle (`abe`)

Test **manuel, dans l'interface**, du module `org.openconcerto.modules.project`
version `1.1`, avec le compte **`abe`** (Gisèle), sur la société
**KINETIC-THERM (42)**.

Durée : **20 à 25 minutes**. Aucun SQL, aucun droit à modifier.

But : vérifier que tout ce qui a été corrigé depuis le début se voit bien **avec
son compte**, et pas seulement avec un compte administrateur :

| Ce qui est vérifié | Partie |
|---|---|
| le module est bien à jour sur son poste | 0 |
| elle trouve le menu de paramétrage (c'est elle qui a le plus de droits) | 1 |
| les en-têtes de colonnes sont lisibles (`Client`, pas `ID_CLIENT`, pas de capitales) | 2 |
| l'affaire se voit sur une **commande fournisseur** neuve | 3 |
| l'affaire se voit quand on **modifie** une facture fournisseur (son cas d'origine) | 4 |
| la colonne **Affaire** est présente **dans le tableau des lignes** | 4 bis |
| le **transfert commande fournisseur → facture** ne plante plus | 5 |
| l'affaire se voit aussi sur les documents **clients** | 6 |
| l'historique des affaires s'ouvre et se ferme **sans erreur** | 7 |

> **Avant de commencer** : tout se fait sur une affaire de test. Créer (ou
> choisir) une affaire nommée **`RECETTE-GISELE`** et ne travailler que sur elle.
> Les documents créés peuvent être supprimés à la fin.

---

## 0. Préparation (3 min)

| ☐ | # | Action | Résultat attendu |
|---|---|---|---|
| ☐ | 0.1 | Fermer **complètement** le client OpenConcerto (pas seulement la fenêtre : quitter l'application) | le client est fermé |
| ☐ | 0.2 | Vérifier que le fichier `org.openconcerto.modules.project-1.1.jar` fait **270 362 octets** (release `v1.1-colonne-affaire`) — Aide → Informations → « Dossiers des modules » | taille exacte ; si elle diffère, le jar n'est pas le bon → me le dire avant de continuer |
| ☐ | 0.3 | Relancer le client et se connecter avec **`abe`** | connexion réussie |
| ☐ | 0.4 | Ouvrir la société **KINETIC-THERM (42)** | la société s'ouvre |
| ☐ | 0.5 | Ouvrir **Gestion → Historique des affaires** | la fenêtre s'ouvre (sert à créer l'affaire de test) |
| ☐ | 0.6 | Créer l'affaire **`RECETTE-GISELE`** (ou noter une affaire existante à réutiliser) | elle apparaît dans la liste de gauche de l'historique |

---

## 1. Elle doit trouver le menu de paramétrage (2 min)

Le module réserve le réglage **au compte qui a le plus de droits dans la base**.
D'après le journal du client, ce compte est **Gisèle** : le menu doit donc être
**visible pour elle**, et masqué pour les autres.

| ☐ | # | Action | Résultat attendu |
|---|---|---|---|
| ☐ | 1.1 | Menu **Paramètres** en haut de la fenêtre | **« Libellés des colonnes »** est présent |
| ☐ | 1.2 | Si absent, regarder le menu **Structure → Paramètres** (repli prévu si le client refuse la création du menu) | le menu s'y trouve |
| ☐ | 1.3 | Ouvrir l'écran | il s'ouvre, titre « Libellés des colonnes — pour toute l'équipe », avec la mention **Utilisateur : Gisèle** |
| ☐ | 1.4 | Regarder la colonne **Automatique** | `Fournisseur`, `Mouvement`, `Salaire`, `User common create`… : **première lettre en majuscule, pas de capitales** |
| ☐ | 1.5 | **Fermer** l'écran sans rien enregistrer | aucune modification, aucune erreur |

> Si le menu est absent : noter la ligne du journal qui commence par
> `[module project] menu « Libellés des colonnes »` (voir partie 8) et me
> l'envoyer. Elle dit qui a le droit et pourquoi le menu est masqué.

---

## 2. Les en-têtes de colonnes sont lisibles (3 min)

| ☐ | # | Action | Résultat attendu |
|---|---|---|---|
| ☐ | 2.1 | **Achats → Commandes fournisseurs** | la liste s'ouvre sans erreur |
| ☐ | 2.2 | Regarder les en-têtes | plus aucun `ID_…` : on lit `Fournisseur`, `Date`, `Numéro`… |
| ☐ | 2.3 | Vérifier la casse | pas de titre entièrement en capitales (`FOURNISSEUR` serait anormal) |
| ☐ | 2.4 | **Ventes → Clients** | en-têtes `Client`, `Nom`, `Ville`… (pas `ID_CLIENT`) |
| ☐ | 2.5 | **Ventes → Factures** | idem, aucun `ID_…` |
| ☐ | 2.6 | Cliquer sur un en-tête pour **trier** | le tri fonctionne, l'en-tête ne change pas |

> Si elle voit un libellé bizarre en capitales (par exemple
> `FOURNISSEURES`), ce n'est pas un bug : c'est un **libellé saisi à la main**
> par l'équipe. Le corriger se fait dans l'écran de la partie 1 (double-clic sur
> la case, corriger, « Enregistrer pour l'équipe »).

---

## 3. Affaire sur une **commande fournisseur** neuve (3 min)

| ☐ | # | Action | Résultat attendu |
|---|---|---|---|
| ☐ | 3.1 | **Achats → Commandes fournisseurs → Nouveau** | un formulaire de commande s'ouvre |
| ☐ | 3.2 | Choisir un fournisseur et une date | champs renseignés |
| ☐ | 3.3 | Chercher le champ **Affaire** | il est **présent** dans l'en-tête (à côté du fournisseur / de la date) |
| ☐ | 3.4 | Saisir `RECETTE-GISELE` | l'affaire se sélectionne, son nom s'affiche |
| ☐ | 3.5 | Ajouter une ligne (un article, une quantité) | la ligne apparaît |
| ☐ | 3.6 | **Enregistrer** | aucune erreur, la commande est enregistrée |
| ☐ | 3.7 | Revenir à la liste des commandes fournisseurs | la commande y est |
| ☐ | 3.8 | Regarder la colonne **Affaire** de cette ligne | `RECETTE-GISELE` |
| ☐ | 3.9 | Clic droit sur la ligne → **Historique affaire** | l'historique s'ouvre, **déjà positionné** sur `RECETTE-GISELE` |
| ☐ | 3.10 | Onglet **Commandes fournisseurs** de l'historique | la commande de 3.6 y figure |

---

## 4. Affaire sur une **facture fournisseur** que l'on modifie (3 min)

C'est le cas d'origine : « je mets l'affaire, et elle ne s'affiche pas ».

| ☐ | # | Action | Résultat attendu |
|---|---|---|---|
| ☐ | 4.1 | **Achats → Factures fournisseurs → Nouveau** | formulaire de facture |
| ☐ | 4.2 | Renseigner fournisseur, date, une ligne — **sans** toucher au champ Affaire | — |
| ☐ | 4.3 | **Enregistrer** | la facture existe, la colonne **Affaire est vide** (normal) |
| ☐ | 4.4 | Historique des affaires, affaire `RECETTE-GISELE`, onglet **Factures fournisseurs** | cette facture **n'y est pas** (normal : pas d'affaire) |
| ☐ | 4.5 | Revenir à la liste, sélectionner la facture, **Modifier** (ou double-clic) | le formulaire s'ouvre en modification |
| ☐ | 4.6 | Saisir l'affaire `RECETTE-GISELE` puis **Enregistrer** | aucune erreur |
| ☐ | 4.7 | Colonne **Affaire** dans la liste | `RECETTE-GISELE` |
| ☐ | 4.8 | Historique des affaires, onglet **Factures fournisseurs** | la facture **apparaît** maintenant |
| ☐ | 4.9 | Refaire 4.5 en **changeant** l'affaire pour une autre, puis enregistrer | la liste et l'historique suivent le changement |

---

## 4 bis. La colonne **Affaire** dans le tableau des lignes (3 min)

C'est la dernière remarque : « dans le tableau je ne vois toujours pas
l'affaire ». Le champ Affaire de l'en-tête est bien rempli ; ce qui manquait est
une **colonne dans le tableau des lignes**.

| ☐ | # | Action | Résultat attendu |
|---|---|---|---|
| ☐ | 4bis.1 | Ouvrir une **commande fournisseur** déjà rattachée à une affaire (par exemple `11870-PO-007-Avt1`, ou celle créée en 3.6) | le détail de la commande s'ouvre |
| ☐ | 4bis.2 | Regarder le tableau des lignes, **juste après la colonne « Désignation »** | une colonne **`Affaire`** est présente, texte noir sur fond blanc |
| ☐ | 4bis.3 | Lire la valeur de cette colonne sur chaque ligne | le **numéro** de l'affaire du document, par exemple **`11870`** (ou `RECETTE-GISELE` pour l'affaire de test) |
| ☐ | 4bis.4 | Essayer de modifier cette case (double-clic) | **impossible** : la colonne est en lecture seule (c'est voulu : l'affaire se change sur le document) |
| ☐ | 4bis.5 | Changer l'affaire du document, enregistrer, rouvrir | la colonne affiche la **nouvelle** valeur |
| ☐ | 4bis.6 | Retirer l'affaire du document, enregistrer, rouvrir | la colonne est **vide** (pas de texte bizarre) |
| ☐ | 4bis.7 | Refaire 4bis.1 sur une **facture fournisseur** | même colonne `Affaire`, même valeur |
| ☐ | 4bis.8 | Refaire 4bis.1 sur une **commande client** (ou un devis) | même colonne `Affaire` |

> Si la colonne n'apparaît pas : vérifier que le jar fait bien **270 362
> octets** (release **`v1.1-colonne-affaire`**), puis me l'écrire — le journal du client contient une ligne `Affaire : colonne …` qui
> dit ce que le module a fait.

---

## 5. Transfert commande fournisseur → facture (3 min)

C'est **son ancien blocage** :
`ID_COMMANDE_ELEMENT is not in table /FACTURE_FOURNISSEUR_ELEMENT/`.

| ☐ | # | Action | Résultat attendu |
|---|---|---|---|
| ☐ | 5.1 | **Gestion → Commandes fournisseurs** | la liste s'ouvre |
| ☐ | 5.2 | Sélectionner la commande créée en 3.6 | ligne sélectionnée |
| ☐ | 5.3 | Clic droit → **Transfert vers saisie achat** (ou bouton équivalent) | **aucune erreur** ; une facture fournisseur s'ouvre, pré-remplie |
| ☐ | 5.4 | Vérifier le champ **Affaire** de cette nouvelle facture | `RECETTE-GISELE` (reprise automatique de la commande) |
| ☐ | 5.5 | Vérifier les lignes | elles reprennent l'article et la quantité de la commande |
| ☐ | 5.6 | **Enregistrer** | la facture est créée |
| ☐ | 5.7 | **Achats → Factures fournisseurs** | la facture est là, colonne **Affaire** = `RECETTE-GISELE` |
| ☐ | 5.8 | Historique des affaires, onglet **Factures fournisseurs** | elle apparaît |

> Si l'erreur `ID_COMMANDE_ELEMENT is not in table` revient : le correctif SQL
> du 1.7.6 **n'est pas appliqué sur cette base**. Ce n'est pas un défaut du
> module. Envoyer la capture, le correctif est dans
> `docs/message-pere-openconcerto-1.7.6.md`.

---

## 6. Les documents **clients** aussi (3 min)

| ☐ | # | Action | Résultat attendu |
|---|---|---|---|
| ☐ | 6.1 | **Ventes → Bons de commande → Nouveau**, avec l'affaire `RECETTE-GISELE`, une ligne, puis enregistrer | enregistrement sans erreur |
| ☐ | 6.2 | Colonne **Affaire** de la liste | `RECETTE-GISELE` |
| ☐ | 6.3 | Historique des affaires, onglet **Bons de commande** | le bon de commande y figure |
| ☐ | 6.4 | **Ventes → Factures → Nouveau** (ou transfert du bon de commande), affaire `RECETTE-GISELE`, enregistrer | facture créée |
| ☐ | 6.5 | Modifier l'affaire de cette facture (double-clic → changer → enregistrer) | la colonne Affaire suit |
| ☐ | 6.6 | Historique des affaires, onglet **Factures** | la facture y figure |
| ☐ | 6.7 | **Ventes → Devis** : ouvrir un devis existant et regarder le champ Affaire | le champ est présent (l'affaire est native dans le cœur pour les devis) |
| ☐ | 6.8 | Ouvrir l'onglet **Avoirs** de l'historique | l'onglet s'ouvre (même vide), sans message d'erreur |

---

## 7. Historique des affaires : ouverture et fermeture sans erreur (2 min)

C'est l'ancien crash : `UncaughtException … "this.jListePanel" is null`.

| ☐ | # | Action | Résultat attendu |
|---|---|---|---|
| ☐ | 7.1 | **Gestion → Historique des affaires**, choisir `RECETTE-GISELE` | l'historique s'affiche |
| ☐ | 7.2 | Passer sur **chaque onglet** : Devis, Bons de commande, Factures, Avoirs, Bons de livraison clients, Demandes de prix, Bons de réception fournisseurs, Commandes fournisseurs, Achats, Factures fournisseurs, Avoirs fournisseurs, Articles commandés | chaque onglet s'ouvre ; **aucune boîte d'erreur** |
| ☐ | 7.3 | Vérifier que les onglets ne sont pas tous vides « pour rien » : ceux des documents créés en 3/4/5/6 contiennent leurs lignes | les documents de test sont visibles |
| ☐ | 7.4 | **Fermer** la fenêtre | aucune boîte « UncaughtException » |
| ☐ | 7.5 | Rouvrir puis refermer, **3 fois de suite** | aucune erreur, à chaque fois |
| ☐ | 7.6 | Fermer le client normalement | aucune erreur |

---

## 8. Si quelque chose ne va pas : ce que je dois recevoir

1. **Le numéro de l'étape** qui a échoué (par exemple « 4.7 : la colonne Affaire
   reste vide »).
2. **Une capture d'écran** de la liste ou de la fenêtre concernée, en-têtes
   visibles.
3. **Les lignes du journal du client** qui commencent par `[module project]`.
   Où les trouver :
   - dans la console si le client est lancé en mode console (voir ci-dessous) ;
   - sinon, dans le fichier de log du client (Aide → Informations indique le
     dossier des journaux).
4. Pour les en-têtes qui resteraient techniques, relancer **une fois** le client
   en ajoutant l'option `-Dproject.labels.debug=true` : chaque colonne non
   reconnue est alors tracée.

---

## 9. Fiche de retour (à remplir et me renvoyer)

| Partie | OK | KO | Remarque / capture |
|---|---|---|---|
| 0. Module à jour (250 074 o) | ☐ | ☐ | |
| 1. Menu « Libellés des colonnes » visible pour Gisèle | ☐ | ☐ | |
| 1.4. Colonne « Automatique » sans capitales | ☐ | ☐ | |
| 2. En-têtes lisibles dans les listes | ☐ | ☐ | |
| 3. Affaire sur commande fournisseur neuve | ☐ | ☐ | |
| 4. Affaire sur facture fournisseur **modifiée** | ☐ | ☐ | |
| 5. Transfert commande → facture fournisseur | ☐ | ☐ | |
| 6. Affaire sur les documents clients | ☐ | ☐ | |
| 7. Historique : ouverture / fermeture sans erreur | ☐ | ☐ | |

---

## 10. Ce que cette recette prouve, et ce qu'elle ne prouve pas

**Prouve** : avec un compte « métier » réel (celui qui a le plus de droits, mais
qui n'a pas installé le module), le rattachement à une affaire est visible et
enregistrable, y compris en modification ; le transfert ne plante plus ;
l'historique ne produit plus d'exception ; les libellés de colonnes sont
appliqués pour elle.

**Ne prouve pas** : le comportement sur un poste où le jar n'est **pas** à jour
(partie 0), ni une base où le correctif SQL de 1.7.6 manque (partie 5). Ces deux
points se vérifient séparément.
