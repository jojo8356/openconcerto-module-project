# Tester le module « project » dans l'interface graphique

Procédure **100 % graphique** (client OpenConcerto 1.7.6, poste de travail) :
aucune commande, aucun SQL. Le seul point technique est le redémarrage du
client après avoir posé le nouveau jar.

---

## 0. Pré-requis (une seule fois)

### 0.1 Où poser le jar (le piège principal)

OpenConcerto charge ses modules dans le dossier `Modules` **relatif au
répertoire de lancement du client** (`Gestion.MODULES_DIR = new File("Modules")`).
Un jar copié dans un dossier `Modules` qui n'est pas lu est **silencieusement
ignoré** : le bouton n'apparaît jamais et rien ne le signale.

Pour connaître les bons dossiers : dans le client, menu **? / Informations**
→ ligne **« Dossiers des modules »** (par exemple `/opt/openconcerto/Modules`
et `~/.local/share/OpenConcerto/Modules`).

La pose se fait avec le script de build, qui installe dans tous les dossiers
connus :

```sh
bash scripts/build-module-client.*
```

Si un dossier système n'est pas modifiable :

```sh
sudo mkdir -p /opt/openconcerto/Modules
sudo cp ~/openconcerto-module-project/build/*.jar /opt/openconcerto/Modules/
```

### 0.2 Version du module

Le client peut déjà embarquer une version du module « Gestion Projet »
(celle de l'installation d'OpenConcerto). Pour que **notre** jar soit
retenu, il doit porter une version **supérieure** : la version du module est
dans `module.properties` (actuellement `1.2`).

Contrôle dans le client : menu **Administration → Gestion des modules** → la
ligne **« Gestion Projet »** doit indiquer **v1.2** et l'état **Démarré**
(l'ancienne v1.1 doit être passée « Disponible »).

### 0.3 Redémarrage

**Redémarrer complètement le client** après la copie du jar : le menu du
module et le bouton ne sont enregistrés qu'au démarrage.

---

## 1. Tester le transfert « demande de prix » → « commande fournisseur »

### 1.1 Ouvrir l'historique des affaires

- Menu **Gestion Projet** → **Historique des affaires**.

> Si le menu « Gestion Projet » est absent : le jar n'a pas été posé dans le
> dossier `Modules`, ou le client n'a pas été redémarré, ou le module n'est pas
> installé (menu *Administration → Gestion des modules*).

### 1.2 Se placer sur une affaire

- En haut à gauche de la fenêtre, le combo **« Affaires »** : choisir une
  affaire ayant des demandes de prix (ou « Toutes les affaires »).
- Le bas de la fenêtre affiche le **bilan** de l'affaire sélectionnée : c'est la
  référence pour comparer avant / après.

### 1.3 Onglet « Demandes de prix »

- Cliquer sur l'onglet **« Demandes de prix »** (entre « Demandes d'achat » et
  « Bons de livraison clients »).
- Si l'onglet est vide : créer une demande de prix avec le bouton **« + »**
  (Ajouter) de la liste, puis double-cliquer sur la ligne pour ouvrir sa fiche
  et saisir au moins **une ligne d'article** (désignation + quantité), puis
  enregistrer et refermer.

### 1.4 Lancer le transfert

- **Cliquer une seule ligne** de demande de prix (une seule : le bouton est
  volontairement désactivé sur une sélection multiple).
- Le bouton **« Transfert en commande fournisseur »** apparaît dans la barre
  d'outils de l'onglet (et aussi dans le menu contextuel par un clic droit sur
  la ligne).
- Cliquer dessus.

> Si le bouton est absent : vérifier le point 0 (dossier `Modules` lu par le
> client et version 1.2 affichée dans « Gestion des modules »).

### 1.5 Contrôler la commande créée

Une fenêtre de saisie de **commande fournisseur** s'ouvre. Vérifier :

| Ce qu'on voit | Ce qui est attendu |
|---|---|
| Fournisseur | repris de la demande de prix |
| Affaire | la même affaire que la demande de prix |
| Date | repris de la demande de prix |
| Lignes (désignation, quantité, unité) | **recopiées** de la demande de prix |
| Prix unitaire, total HT, total TTC | repris de la demande de prix : **à corriger** avec le prix du fournisseur (les totaux sont recalculés par OpenConcerto) |

Si les lignes sont recopiées **avec** des prix ou des totaux, c'est anormal :
prévenir, c'est un défaut à corriger.

### 1.6 Enregistrer

- Saisir le prix unitaire du fournisseur sur chaque ligne (les totaux se
  recalculent), puis **Enregistrer**.
- La commande est créée : elle apparaît dans l'onglet **« Commandes
  fournisseurs »** du même historique, rattachée à l'affaire.

### 1.7 Vérifier le lien entre les deux documents

Le lien demande de prix → commande est mémorisé par le mécanisme standard
d'OpenConcerto dans la table `TR_DEMANDE_PRIX`.

Dans le client : menu **Administration → Terminal SQL**, puis :

```sql
SELECT * FROM "TR_DEMANDE_PRIX";
```

Une ligne doit apparaître avec l'id de la demande de prix et l'id de la
commande créée.

### 1.8 Vérifications complémentaires

- Onglet **« Commandes fournisseurs »** de l'historique : la nouvelle commande
  est là, avec le bon numéro et le bon fournisseur.
- Menu **Fournisseurs** → **Commandes fournisseurs** : la commande existe aussi
  de ce côté.
- Le **bilan** de l'affaire (en bas de l'historique) a évolué : la commande
  compte désormais dans les achats.
- La demande de prix d'origine **reste ouverte** : le transfert ne la clôture
  pas (c'est un choix, à changer si on le souhaite).

---

## 2. Tester le reste du module « project » (non-régression)

Le module project ajoute des onglets et des boutons dans le client. Les
vérifier après l'installation du nouveau jar :

### 2.1 Les onglets de l'historique

Dans **Gestion Projet → Historique des affaires**, vérifier que les onglets
suivants s'affichent et se chargent sans erreur (un onglet vide ou une
exception au démarrage est un défaut) :

Devis · Bons de commande · Chiffrage · Factures · Avoirs · Demandes d'achat ·
Demandes de prix · Bons de livraison clients · Commandes fournisseurs ·
Articles commandés · Bons de réception fournisseurs · Articles réceptionnés ·
Achats · Factures fournisseurs · Avoirs fournisseurs · (Temps) · (Stock) ·
(Note de frais) · (Pointage).

> Certains onglets n'apparaissent que si la table correspondante existe
> (par exemple « Stock », « Note de frais », « Pointage »).

### 2.2 Le bouton sur un devis

- Onglet **« Devis »** → sélectionner un devis → le bouton **« Transformer en
  commande »** doit toujours être présent (c'est le transfert historique du
  module, il ne doit pas avoir été cassé par le nouveau code).

### 2.3 Les panneaux de saisie

- Menu **Gestion Projet → Liste des affaires** : la liste des affaires
  s'affiche, on peut l'ouvrir et l'éditer.
- Menu **Gestion Projet → Saisie affaire** : le formulaire d'une affaire
  s'ouvre.
- Historique des affaires → onglet **« Factures »** / **« Bons de livraison
  clients »** : double-cliquer sur une ligne ouvre la fiche correspondante
  (le module y ajoute des actions, elles ne doivent plus planter).

### 2.4 Le bilan

- En bas de l'historique, le bilan de l'affaire s'affiche (montants achats /
  ventes). Il doit se calculer sans erreur.

---

## 3. Que faire si ça ne marche pas

| Symptôme | Cause probable | Solution |
|---|---|---|
| Le menu « Gestion Projet » n'est pas là | jar non posé / client non redémarré | reposer le jar, redémarrer le client |
| L'onglet « Demandes de prix » est absent | le module *supplychain* n'est pas installé (il fournit `DEMANDE_PRIX`) | installer le module supplychain |
| Le bouton « Transfert en commande fournisseur » n'apparaît pas | la table `DEMANDE_PRIX_ELEMENT` n'existe pas, ou le client n'a pas été redémarré après la pose du jar | redémarrer le client ; si l'onglet « Demandes de prix » est vide, la table des lignes manque |
| Le bouton est grisé | aucune ligne sélectionnée, ou plusieurs lignes sélectionnées | ne sélectionner qu'**une** demande de prix |
| Erreur « No table transfer for DEMANDE_PRIX » à l'enregistrement | la table technique `TR_DEMANDE_PRIX` n'a pas pu être créée (droits de création de table, ou base en lecture seule) | vérifier les droits de l'utilisateur sur la base ; le client la crée tout seul au démarrage |
| Les lignes sont recopiées avec des prix | défaut du mapping | le signaler (les totaux ne doivent jamais être recopiés) |
