# Module autonome « Gestion des devises »

Ce dossier contient un **module OpenConcerto indépendant** (`org.openconcerto.modules.currency`). Il ne modifie pas le module Projet et ne crée pas de deuxième catalogue de devises.

## Fonctionnalités

- Réutilise la table OpenConcerto `DEVISE` (code, taux et taux commercial) et donne un raccourci vers sa liste.
- Rend la devise du client (`CLIENT.ID_DEVISE`) sélectionnable dans la fiche client et l'affiche dans la liste des clients.
- Ajoute aussi à la liste clients l'action **Choisir / modifier la devise du client** : un vrai `ElementComboBox` ouvre le catalogue `DEVISE`, puis le choix est enregistré dans `CLIENT.ID_DEVISE` après vérification du droit OpenConcerto de modifier le client. Ce chemin explicite reste disponible même si le formulaire client ouvert ne permet que la consultation.
- Ajoute la liaison `CLIENT.ID_DEVISE -> DEVISE` uniquement si elle manque dans une base personnalisée. La table `DEVISE` n'est jamais recréée.
- Pour les devis, commandes client, factures client et avoirs client, choisit un modèle XML/ODS optionnel en fonction du code de devise du client.
- Si le modèle spécifique à la devise n'existe pas, conserve le modèle qu'OpenConcerto aurait normalement utilisé.
- Au démarrage, synchronise en tâche de fond les codes ISO 4217 depuis la liste XML officielle de SIX. Une action de menu permet de relancer la synchronisation à tout moment.

## Synchronisation du catalogue

Le module télécharge la liste officielle « List One: Current Currency & Funds » de SIX, déduplique les entrées par code ISO, ignore les territoires sans code de devise, puis ajoute les codes manquants dans `DEVISE`. Si la base propose un champ `NOM`, son libellé est actualisé. Une devise archivée qui redevient courante est réactivée. Les lignes historiques et les devises locales sont conservées : aucune ligne n'est supprimée.

Le XML est traité avec les DTD et entités externes désactivées, des délais réseau sont appliqués, et la réponse doit contenir au moins 150 codes distincts avant toute écriture. Si le site est indisponible ou renvoie un document incomplet, la synchronisation échoue proprement : la base existante est conservée, une erreur est inscrite dans le journal et le démarrage d'OpenConcerto continue. Relance manuelle via **Listes > Synchroniser le catalogue ISO 4217**.

La source SIX contient les codes et unités ISO, pas les taux de change. Les taux déjà présents (`TAUX`, `TAUX_COMMERCIAL`) ne sont jamais écrasés. Les nouveaux codes sont initialisés à `1` par compatibilité avec le formulaire OpenConcerto : configurez leur taux réel dans la fiche devise avant toute conversion comptable.

Dans la liste clients, sélectionnez une seule ligne puis utilisez **Choisir / modifier la devise du client** (bouton d'action ou menu contextuel), choisissez une devise et validez. La sélection est enregistrée dans `CLIENT.ID_DEVISE`, clé étrangère vers `DEVISE.ID`. L'action vérifie le droit de modification OpenConcerto avant toute écriture. Pour joindre facilement les deux tables :

```sql
SELECT c.ID, c.NOM, d.CODE
FROM CLIENT c
LEFT JOIN DEVISE d ON d.ID = c.ID_DEVISE;
```

## Modèles par devise

Le suffixe est un code ISO à trois lettres, en majuscules :

| Document | Modèle de base | Exemple USD |
| --- | --- | --- |
| Devis | `Devis` | `Devis_USD.ods` et `Devis_USD.xml` |
| Commande client | `CommandeClient` | `CommandeClient_USD.ods` et `CommandeClient_USD.xml` |
| Facture client | `VenteFacture` | `VenteFacture_USD.ods` et `VenteFacture_USD.xml` |
| Avoir client | `Avoir` | `Avoir_USD.ods` et `Avoir_USD.xml` |

Les fichiers se placent dans le répertoire de modèles OpenConcerto habituel, par exemple `Configuration/Template/Default/`. Si le client a une langue configurée, utilisez aussi le sous-répertoire de langue habituel.

La sélection de modèle explicite d'OpenConcerto est respectée : pour un modèle dont l'identifiant est `FactureInternationale`, le module recherche `FactureInternationale_USD`.

OpenConcerto distingue certains types de facture en ajoutant le type au nom du modèle. Pour une facture d'acompte en USD, utilisez donc le modèle typé correspondant (par exemple `VenteFacture_USDAcompte.ods`, avec son XML `VenteFacture_USDAcompte.xml`). Le module ne bascule sur un modèle devise que si ce modèle existe pour la langue et le type de document concernés.

### Afficher le code devise dans un XML

Dans la définition XML du document, les clés étrangères se parcourent par des champs imbriqués. Depuis un devis ou une facture, le chemin vers le code de devise du client est :

`ID_CLIENT -> ID_DEVISE -> CODE`

Exemple de fragment XML (adapter la cellule `location` au modèle) :

```xml
<element location="B2">
    <field name="ID_CLIENT">
        <field name="ID_DEVISE">
            <field name="CODE" />
        </field>
    </field>
</element>
```

## Limite fonctionnelle importante

Le module choisit un modèle de document et permet au XML d'afficher la devise du client. **Il ne convertit pas les montants HT/TVA/TTC et ne change pas les règles comptables** : les tarifs, lignes et taux restent ceux calculés par OpenConcerto. Le choix d'une devise client ne remplace donc pas une configuration complète de facturation multidevise ou de conversion comptable.

## Compiler et tester

Les tests unitaires du sélecteur de modèles, de la règle de persistance du choix et du parseur ISO 4217 ne nécessitent pas le JAR OpenConcerto. Le parcours Swing et l'écriture réelle en base restent à valider dans une instance OpenConcerto 1.7.6 :

```sh
sh currency-module/scripts/run-tests.sh
```

Pour construire le JAR Java 8, fournir le JAR de l'installation OpenConcerto 1.7.6 :

```sh
OPENCONCERTO_JAR=/chemin/vers/OpenConcerto.jar ./currency-module/scripts/build-java8-compatible.sh
```

Le JAR produit est `currency-module/build/org.openconcerto.modules.currency-1.0.jar`. Installez-le dans le répertoire `Modules` de l'installation OpenConcerto, puis activez le module depuis le gestionnaire de modules.
