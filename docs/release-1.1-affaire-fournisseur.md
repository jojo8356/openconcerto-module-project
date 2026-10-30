# Module project 1.1 — l'affaire des commandes et factures fournisseurs s'affiche

**Jar :** `org.openconcerto.modules.project-1.1.jar`
**Version déclarée (`module.properties`) :** `1.1` — inchangée, comme demandé
**Cible :** OpenConcerto 1.7.6 (bytecode Java 8, fonctionne sur JRE 8 et plus)
**Branche :** `arena/ff79607f-openconcerto-module-project`

---

## 1. Ce qui est corrigé

Le symptôme : « je mets une affaire sur une commande ou une facture
fournisseur, elle ne s'affiche pas ».

Cinq causes, toutes corrigées :

| # | Cause | Effet avant le correctif | Après |
|---|---|---|---|
| D1 | `FACTURE_FOURNISSEUR` absente de la liste des tables à affaire du module | aucune colonne « Affaire » dans la liste des factures fournisseurs, aucune action « Historique affaire », colonne jamais créée | la facture fournisseur est une table à affaire comme les autres |
| D2 | colonnes `ID_AFFAIRE` créées seulement à la **première** installation, et pour 4 tables au démarrage | sur une base existante, `COMMANDE`, `SAISIE_ACHAT`, `AVOIR_FOURNISSEUR`… pouvaient rester sans colonne : l'affaire n'était **pas enregistrable** | `ensureAffairColumns` vérifie et répare **à chaque démarrage** |
| D3 | colonne créée par une seule instruction `ADD COLUMN … REFERENCES` | un document pointant vers une affaire supprimée faisait échouer toute l'instruction : la colonne n'était **jamais** créée (erreur seulement imprimée dans la console) | colonne d'abord, contrainte `FOREIGN KEY … NOT VALID` ensuite |
| D4 | onglets de l'historique enregistrés sans vérifier qu'ils sont filtrables | une table sans `ID_AFFAIRE` faisait lever une exception au milieu de la boucle de `ListeHistoriquePanel` : **tous les onglets suivants** restaient non filtrés, donc vides | seuls des onglets réellement filtrables sont enregistrés |
| D5 | lignes filtrées directement sur `ID_AFFAIRE` | les lignes dont l'affaire de ligne est vide (le cas normal) disparaissaient de l'historique | les lignes sont filtrées par leur document parent |

Sont concernés : `COMMANDE` (commandes fournisseurs), `FACTURE_FOURNISSEUR`
(factures fournisseurs), `SAISIE_ACHAT` (achats), `AVOIR_FOURNISSEUR` (avoirs
fournisseurs) et leurs lignes (`COMMANDE_ELEMENT`, `FACTURE_FOURNISSEUR_ELEMENT`,
`BON_RECEPTION_ELEMENT`).

## 2. À l'installation

1. **Sauvegarder la base** (le module ajoute des colonnes, il ne supprime rien).
2. Arrêter le client.
3. Copier le jar **directement dans le dossier `Modules` lu par le client**
   (majuscule, pas de sous-dossier), et **retirer** l'ancien jar du même
   module pour n'en laisser qu'un seul.
   - Le bon chemin se lit dans le client : menu **? / Aide → Informations**,
     ligne **« Dossiers des modules »**.
   - Chemins habituels :
     - Linux, client lancé depuis `/opt/openconcerto` → `/opt/openconcerto/Modules/`
     - Linux, client extrait dans le dossier personnel → `~/OpenConcerto-1.7.6/Modules/`
     - Linux, dossier de données → `~/.local/share/OpenConcerto/Modules/`
     - Windows → `C:\Program Files\OpenConcerto\Modules\` (ou le chemin
       affiché par *Informations*)
     - macOS → `…/OpenConcerto.app/Contents/…/Modules/`
   - En cas de doute, poser le jar dans **tous** les dossiers `Modules`
     trouvés : celui du client est forcément l'un d'eux. Script fourni :
     `sh scripts/installer-jar-release.sh --jar <chemin du jar>`.
4. Redémarrer le client, se connecter à la société.

> Une fois posé, vérifier dans **Informations → Gestion des modules** que notre
> module est listé en **1.1**. Si le client refuse de démarrer avec
> `NO_FACTORY=[Module org.openconcerto.modules.project v1.1]`, la base épingle
> une autre version : voir `docs/release-process.md` §5.1
> (`scripts/fix-module-version.sh`).

Au démarrage, la console peut afficher :

```
[module project] colonnes ID_AFFAIRE creees : [COMMANDE, SAISIE_ACHAT, ...]
[module project] onglet « ... » ignore : ...
```

- les lignes `colonnes ID_AFFAIRE creees` sont **normales** (réparation de la
  base) ;
- une ligne `onglet ... ignore` signifie que l'onglet concerné n'était pas
  filtrable et a été écarté au lieu de casser tout l'historique ;
- une ligne `colonne ID_AFFAIRE non creee sur ...` est **anormale** : droits
  insuffisants sur la base, à signaler avec son message complet.

## 3. Vérification en 2 minutes

1. **Achats > Commandes fournisseurs** : la colonne **Affaire** est présente.
2. Ouvrir une commande fournisseur, saisir une affaire, enregistrer : la
   colonne « Affaire » de la liste affiche le numéro de l'affaire.
3. Menu du module > **Historique des affaires** (ou « Historique affaire »
   depuis la liste des commandes) : la commande apparaît dans l'onglet
   **Commandes fournisseurs**, ses lignes dans **Articles commandés**.
4. **Achats > Factures fournisseurs** : colonne **Affaire** présente, facture
   visible dans l'onglet **Factures fournisseurs** de l'historique.

Procédure graphique complète, clic par clic :
[`docs/recette-graphique-affaire-fournisseur.md`](./recette-graphique-affaire-fournisseur.md).

## 4. Tests exécutés pour cette version

| Suite | Commande | Résultat |
|---|---|---|
| Java (règles de rattachement) | `sh scripts/run-tests.sh` | 35 + 16 tests OK |
| SQL, base « installation existante » + migration | `sh tests/sql/e2e-affaire-fournisseur.sh` | 26 contrôles, 0 échec |
| Scénario création commande + facture fournisseur, puis modification de leur affaire | `sh tests/sql/scenario-creation-fournisseur.sh` | 71 contrôles, 0 échec |
| Mutations (le correctif est-il vraiment testé ?) | `sh scripts/test-mutations-affaire.sh` | 10 contrôles, 0 échec |

Tout est rejouable d'une seule commande : `sh scripts/test-affaire-fournisseur.sh`.

Le jar est compilé par le workflow
[`.github/workflows/release.yml`](../.github/workflows/release.yml) contre
**OpenConcerto 1.7.6** officiel, puis contrôlé :

- bytecode Java 8 (toutes les classes ≤ major 52) ;
- `META-INF/openConcertoModule.properties` avec `version=1.1` ;
- présence de `Module`, `AffairLinkSupport`, `ProjectHistory`,
  `SupplierOrderToInvoiceSQLInjector` ;
- empreinte **SHA-256** publiée à côté du jar (`…jar.sha256`).

## 5. Retour arrière

Conserver le jar précédent : remettre l'ancien fichier à la place suffit.
Les colonnes `ID_AFFAIRE` ajoutées restent dans la base ; elles sont inoffensives
pour l'ancienne version (l'ancienne version les ignore, sauf
`FACTURE_FOURNISSEUR` qu'elle connaissait déjà).

## 6. Limites connues (documentées, non corrigées ici)

- Le bilan de l'affaire additionne l'en-tête `FACTURE_FOURNISSEUR.T_HT` **et**
  les lignes `FACTURE_FOURNISSEUR_ELEMENT.T_PA_HT` quand la liste des éléments
  existe : décision fonctionnelle à trancher (double comptage possible).
- Les documents rattachés à une affaire **supprimée** restent invisibles dans
  l'historique (comportement du cœur : jointure sur `AFFAIRE`). Le diagnostic
  les compte et les liste.
