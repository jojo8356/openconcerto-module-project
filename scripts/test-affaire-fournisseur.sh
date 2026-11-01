#!/usr/bin/env sh
#
# Suite complete : « affaire sur les commandes et factures fournisseurs ».
#
# Une seule commande pour rejouer toutes les preuves du correctif :
#
#   1. tests Java des regles de rattachement (AffairLinkSupportTest, ...) ;
#   2. 26 controles SQL de bout en bout sur une base « installation
#      existante » (tests/sql/e2e-affaire-fournisseur.sh) ;
#   3. 71 controles du scenario « creation d'une affaire, d'une commande
#      fournisseur puis de sa facture, et modification de leur affaire »
#      (tests/sql/scenario-creation-fournisseur.sh) ;
#   4. les tests de mutation qui verifient que tout ceci sait echouer
#      (scripts/test-mutations-affaire.sh) ;
#   5. les tests du script d'installation du jar dans le client
#      (tests/installer/test-installer-jar.sh) ;
#   6. les libelles de colonnes (menu Paramètres) : SQL de bout en bout et
#      mutations (tests/sql/e2e-colonnes.sh, scripts/test-mutations-colonnes.sh).
#
# Usage :
#   sh scripts/test-affaire-fournisseur.sh
#   sh scripts/test-affaire-fournisseur.sh --sans-java      (JDK absent)
#   sh scripts/test-affaire-fournisseur.sh --sans-mutations (plus rapide)
#   sh scripts/test-affaire-fournisseur.sh --sans-java --sans-mutations
#
# Prerequis : node + npm (pglite, installe automatiquement) ; un JDK pour la
# partie Java. Le script s'arrete avec un code non nul si une suite echoue.
#
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
AVEC_JAVA=1
AVEC_MUTATIONS=1

for option in "$@"; do
    case "$option" in
        --sans-java) AVEC_JAVA=0 ;;
        --sans-mutations) AVEC_MUTATIONS=0 ;;
        -h|--help)
            awk 'NR > 1 && $0 == "set -eu" { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"
            exit 0
            ;;
        *)
            printf 'option inconnue : %s (utiliser --help)\n' "$option" >&2
            exit 2
            ;;
    esac
done

ETAPES=0
ECHECS=0

lancer() {
    description=$1
    script=$2
    ETAPES=$((ETAPES + 1))
    printf '\n=== %s ===\n' "$description"
    if (cd "$ROOT_DIR" && sh "$script"); then
        return 0
    fi
    ECHECS=$((ECHECS + 1))
    printf '!!! ECHEC : %s\n' "$description"
    return 0
}

if [ "$AVEC_JAVA" -eq 1 ]; then
    if command -v javac >/dev/null 2>&1 && command -v java >/dev/null 2>&1; then
        lancer "tests Java (regles de rattachement, transfert commande -> facture)" scripts/run-tests.sh
    else
        printf 'javac/java absents : partie Java ignoree (--sans-java pour le taire)\n'
    fi
else
    printf 'partie Java ignoree (--sans-java)\n'
fi

lancer "SQL : base « installation existante » et migration du module" tests/sql/e2e-affaire-fournisseur.sh
lancer "scenario : creation d'une commande et d'une facture fournisseur sur une affaire" tests/sql/scenario-creation-fournisseur.sh

if [ "$AVEC_MUTATIONS" -eq 1 ]; then
    lancer "mutations : les tests precedents savent-ils echouer ?" scripts/test-mutations-affaire.sh
else
    printf '\nmutations ignorees (--sans-mutations)\n'
fi

lancer "libelles de colonnes : tables, unicite, transaction, role le plus haut" tests/sql/e2e-colonnes.sh

if [ "$AVEC_MUTATIONS" -eq 1 ]; then
    lancer "mutations des libelles de colonnes" scripts/test-mutations-colonnes.sh
fi

lancer "installation du jar dans le client (dossier Modules)" tests/installer/test-installer-jar.sh

printf '\n==============================================\n'
printf 'Suites executees : %s | suites en echec : %s\n' "$ETAPES" "$ECHECS"
if [ "$ECHECS" -ne 0 ]; then
    printf 'RESULTAT GLOBAL : ECHEC\n'
    exit 1
fi
printf 'RESULTAT GLOBAL : OK\n'
