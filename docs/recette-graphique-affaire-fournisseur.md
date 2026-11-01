# Recette graphique — l'affaire d'une commande / facture fournisseur

Test **manuel, dans l'interface**, du correctif « affaire sur les documents
fournisseurs » (jar `org.openconcerto.modules.project-1.1.jar`).

Durée : 15 à 20 minutes. Tout se fait dans l'ERP, aucun SQL n'est nécessaire.

Les libellés de menus peuvent varier légèrement selon la version et la
configuration ; le *menu du module* est celui qui contient « Liste des
affaires », « Saisie affaire » et « Historique des affaires ».

---

## 0. Préparation (5 min)

| # | Action | Résultat attendu |
|---|---|---|
| 0.1 | Sauvegarder la base (menu du client / outil de sauvegarde habituel) | une sauvegarde existe et est datée |
| 0.2 | Fermer le client, remplacer le jar du module, relancer | le client démarre normalement |
| 0.3 | Ouvrir la console / le fichier de log du client | aucune ligne `[module project] colonne ID_AFFAIRE non creee` |
| 0.4 | Se connecter à la société de test | l'écran d'accueil s'affiche |

> Si la console affiche `[module project] colonnes ID_AFFAIRE creees : [...]`,
> c'est **le correctif qui répare la base** : normal, une seule fois.

## 1. Créer une affaire de test

| # | Action | Résultat attendu |
|---|---|---|
| 1.1 | Menu du module > **Saisie affaire** | formulaire d'affaire |
| 1.2 | Renseigner : numéro `RECETTE-AFFAIRE`, nom `Recette affaire fournisseur`, client, date du jour, état « En cours » | — |
| 1.3 | Enregistrer (bouton **Enregistrer**) | l'affaire apparaît dans **Liste des affaires** |

## 2. Commande fournisseur : créer avec une affaire

| # | Action | Résultat attendu |
|---|---|---|
| 2.1 | **Achats > Commandes fournisseurs** | la liste s'ouvre |
| 2.2 | Vérifier la colonne **Affaire** dans la liste | la colonne existe (même vide) |
| 2.3 | Bouton **Nouveau** | formulaire de commande fournisseur |
| 2.4 | Choisir un fournisseur, renseigner un numéro interne, la date | — |
| 2.5 | **Vérifier que le champ « Affaire » est visible dans l'en-tête du formulaire** | champ présent (point clé du correctif : sans lui, l'affaire n'est pas saisissable) |
| 2.6 | Saisir l'affaire `RECETTE-AFFAIRE` dans ce champ (ou la choisir dans la liste déroulante) | la valeur reste affichée |
| 2.7 | Ajouter 3 lignes d'articles (désignation, quantité, prix d'achat HT) | 3 lignes visibles |
| 2.8 | Enregistrer | — |
| 2.9 | Revenir à la liste des commandes fournisseurs | la commande est présente, la colonne **Affaire** affiche `RECETTE-AFFAIRE` |

> **C'est le point qui échouait avant le correctif** : la commande
> s'enregistrait sans affaire, ou l'affaire n'était pas proposée.

## 3. Historique des affaires : la commande doit apparaître

| # | Action | Résultat attendu |
|---|---|---|
| 3.1 | Menu du module > **Historique des affaires** | fenêtre d'historique avec la liste des affaires et des onglets |
| 3.2 | Sélectionner l'affaire `RECETTE-AFFAIRE` | les onglets se filtrent |
| 3.3 | Onglet **Commandes fournisseurs** | la commande créée en 2.8 est listée (1 ligne) |
| 3.4 | Onglet **Articles commandés** | les 3 lignes saisies sont listées |
| 3.5 | Vérifier les onglets voisins (**Devis**, **Factures**, **Bons de commande**) | ils s'ouvrent sans erreur et sans lever de message d'erreur Java |

> Point clé : avant le correctif, les onglets **suivant** celui qui échouait
> restaient non filtrés (donc vides) ou l'historique affichait une erreur.
> Ici, **aucun** onglet ne doit produire d'erreur.

## 4. Facture fournisseur par transfert : l'affaire doit être reprise

| # | Action | Résultat attendu |
|---|---|---|
| 4.1 | **Achats > Commandes fournisseurs** > sélectionner la commande de 2.8 | ligne sélectionnée |
| 4.2 | Action **Transfert en facture** (bouton de la barre d'outils ou clic droit) | un formulaire de facture fournisseur s'ouvre, pré-rempli |
| 4.3 | Vérifier le champ **Affaire** de l'en-tête | il vaut `RECETTE-AFFAIRE` (reprise automatique de la commande) |
| 4.4 | Vérifier les lignes | elles reprennent les articles de la commande |
| 4.5 | Enregistrer | — |
| 4.6 | **Achats > Factures fournisseurs** | la facture est présente, colonne **Affaire** = `RECETTE-AFFAIRE` |
| 4.7 | Retour à l'**Historique des affaires**, affaire `RECETTE-AFFAIRE`, onglet **Factures fournisseurs** | la facture est listée |

## 5. Facture fournisseur saisie sans affaire : ajouter l'affaire après coup

C'est le cas « je modifie la facture et l'affaire ne s'affiche pas ».

| # | Action | Résultat attendu |
|---|---|---|
| 5.1 | **Achats > Factures fournisseurs** > **Nouveau** | formulaire de facture |
| 5.2 | Renseigner fournisseur, date, montant, **sans** toucher au champ Affaire | — |
| 5.3 | Enregistrer | la facture existe, colonne Affaire **vide** |
| 5.4 | Historique des affaires, affaire `RECETTE-AFFAIRE`, onglet **Factures fournisseurs** | cette facture **n'y est pas** (normal : elle n'a pas d'affaire) |
| 5.5 | Revenir à la liste, sélectionner la facture, **Modifier** (ou double-clic) | formulaire en modification |
| 5.6 | Saisir l'affaire `RECETTE-AFFAIRE` | la valeur s'affiche |
| 5.7 | Enregistrer | — |
| 5.8 | Vérifier la colonne **Affaire** dans la liste | `RECETTE-AFFAIRE` |
| 5.9 | Historique des affaires, onglet **Factures fournisseurs** | la facture **apparaît** maintenant |

Alternative par l'historique : clic droit sur la ligne de la facture >
**Modifier** (action ajoutée par ce correctif sur les factures fournisseurs et
les achats).

## 6. Changer d'affaire, puis retirer l'affaire

| # | Action | Résultat attendu |
|---|---|---|
| 6.1 | Créer une 2e affaire `RECETTE-AFFAIRE-2` (comme en 1) | — |
| 6.2 | Modifier la facture de 5.7, mettre l'affaire `RECETTE-AFFAIRE-2`, enregistrer | — |
| 6.3 | Historique affaire `RECETTE-AFFAIRE` | la facture **n'y est plus** |
| 6.4 | Historique affaire `RECETTE-AFFAIRE-2` | la facture **y est** |
| 6.5 | Modifier la facture, **vider** le champ Affaire, enregistrer | colonne Affaire vide dans la liste |
| 6.6 | Historique affaire `RECETTE-AFFAIRE-2` | la facture **n'y est plus** (aucune erreur, aucun doublon) |

## 7. Cas limites (doivent se comporter proprement)

| # | Cas | Résultat attendu |
|---|---|---|
| 7.1 | Mettre l'affaire « Indéfinie » sur une facture fournisseur | la valeur est enregistrée, mais la facture n'apparaît dans **aucun** historique d'affaire (ligne technique) |
| 7.2 | Saisir une affaire **inexistante** (identifiant inexistant, si l'interface le permet) | refus à l'enregistrement (contrainte de clé étrangère), message d'erreur, valeur non enregistrée |
| 7.3 | Une facture ancienne rattachée à une affaire **supprimée** | elle reste ouvrable dans la liste, mais n'apparaît dans aucun historique (comportement du cœur), **sans** message d'erreur |
| 7.4 | Affaire **close** (« Dossier clos ») | la commande / facture apparaît dans l'historique de cette affaire |

## 8. Non-régression (rapide)

| # | Action | Résultat attendu |
|---|---|---|
| 8.1 | **Ventes > Devis** | colonne Affaire présente, liste fonctionnelle |
| 8.2 | **Ventes > Bons de commande** | idem |
| 8.3 | **Ventes > Factures** | idem |
| 8.4 | **Achats > Bons de réception** | idem |
| 8.5 | Historique d'une affaire cliente existante | onglets Devis / Bons de commande / Factures renseignés comme avant |
| 8.6 | Action **Historique affaire** depuis la liste des factures fournisseurs | la fenêtre s'ouvre sur les bons onglets |

## 9. Grille de recette à cocher

| Contrôle | Attendu | OK |
|---|---|---|
| Champ **Affaire** dans le formulaire de commande fournisseur | présent | ☐ |
| Champ **Affaire** dans le formulaire de facture fournisseur | présent | ☐ |
| Colonne **Affaire** dans les listes commandes / factures fournisseurs | présente et renseignée | ☐ |
| Historique > onglet **Commandes fournisseurs** | la commande est là | ☐ |
| Historique > onglet **Articles commandés** | les lignes sont là | ☐ |
| Historique > onglet **Factures fournisseurs** | la facture est là | ☐ |
| Transfert commande → facture | affaire reprise dans l'en-tête | ☐ |
| Modification de l'affaire d'une facture existante | historique mis à jour | ☐ |
| Changement / retrait d'affaire | plus de doublon, plus de fantôme | ☐ |
| Aucun message d'erreur Java dans la console | — | ☐ |
| Autres onglets de l'historique (devis, ventes) | non régressés | ☐ |

## 10. En cas d'échec : quoi relever

1. **La console du client** : toutes les lignes qui commencent par
   `[module project]`, plus la pile d'appels éventuelle.
2. **La liste exacte** des onglets affichés dans l'historique (une capture).
3. **Le diagnostic lecture seule** (aucune écriture dans la base) :

```sh
sh scripts/diagnostic-affaire-fournisseur.sh --host <serveur> --port 5432 \
   --db OpenConcerto --user openconcerto --schema OpenConcerto42 \
   --affaire <numéro de l'affaire>
```

Il indique : colonne manquante, lignes sans affaire de ligne, documents
pointant vers une affaire supprimée, et le nombre de lignes réellement visibles
par onglet.

4. **Une capture** de la liste (colonne Affaire) et de l'onglet vide.

Avec ces quatre éléments, la cause est identifiable sans accès à la base de
production.
