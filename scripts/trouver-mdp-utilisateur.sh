#!/usr/bin/env bash
#
# Retrouve le mot de passe d'un utilisateur OpenConcerto 1.7 a partir du hash
# stocke dans "Common"."USER_COMMON"."PASSWORD" (SHA-1 + Base64, cf.
# org.openconcerto.sql.ui.Login.encodePassword).
#
# Le hash n'est PAS reversible : on compare donc le hash stocke a une liste de
# mots de passe courants pre-calcules. Si aucun ne correspond, le mot de passe
# est reinitialisable (voir --reset).
#
#   ./trouver-mdp-utilisateur.sh                    # tous les utilisateurs
#   ./trouver-mdp-utilisateur.sh -U abe             # un seul
#   ./trouver-mdp-utilisateur.sh -U abe --reset MDP # remet le mot de passe
#
# Options :
#   -U LOGIN    utilisateur (defaut : tous)
#   -b BASE     base (defaut : OpenConcerto)
#   -H HOTE     hote (defaut : 127.0.0.1)
#   -p PORT     port (defaut : 5433)
#   -R ROLE     role SQL (defaut : openconcerto)
#   -P MDP      mot de passe SQL (defaut : $PGPASSWORD, sinon POSTGRES_PASSWORD du .env)
#   -o DOSSIER  dossier de la stack (defaut : ~/oc-176-docker)
#   --reset MDP reinitialise le mot de passe de l'utilisateur -U
#   -n          n'ecrit rien
#   -h          cette aide
#
set -euo pipefail

LOGIN=""
BASE="OpenConcerto"
HOST="127.0.0.1"
PORT="5433"
ROLE="openconcerto"
PASSWORD="${PGPASSWORD:-}"
STACK_DIR="$HOME/oc-176-docker"
RESET=""
DRY=0

log()  { printf '\n==> %s\n' "$*"; }
info() { printf '  %s\n' "$*"; }
die()  { printf '\nERREUR : %s\n' "$*" >&2; exit 1; }

usage() {
    awk '/^# Options/{f=1} f { if ($0 ~ /^# / || $0 ~ /^$/) print }' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        -U) LOGIN="$2"; shift 2 ;;
        -b) BASE="$2"; shift 2 ;;
        -H) HOST="$2"; shift 2 ;;
        -p) PORT="$2"; shift 2 ;;
        -R) ROLE="$2"; shift 2 ;;
        -P) PASSWORD="$2"; shift 2 ;;
        -o) STACK_DIR="$2"; shift 2 ;;
        --reset) RESET="$2"; shift 2 ;;
        -n) DRY=1; shift ;;
        -h|--help) usage ;;
        *) die "option inconnue : $1" ;;
    esac
done

command -v psql >/dev/null 2>&1 || die "'psql' introuvable."
if [ -z "$PASSWORD" ] && [ -f "$STACK_DIR/.env" ]; then
    PASSWORD=$(sed -n 's/^POSTGRES_PASSWORD=//p' "$STACK_DIR/.env" | head -n 1)
fi

run_sql() {
    PGPASSWORD="$PASSWORD" psql -X -h "$HOST" -p "$PORT" -U "$ROLE" -d "$BASE" -tAc "$1"
}

# --------------------------------------------------------------- liste candidats
# "<hash SHA-1+Base64>\t<mot de passe>" (pre-calcule : le hash n'est pas
# reversible, on ne peut donc pas le calculer a la volee sans dependance).
CANDIDATES=$(cat <<'CANDS'
2jmj7l5rSw0yVb/vlWAYkK/YBwk=	
BthZsEllHNdAKJtJc++293g5Ujg=	openconcerto
0wN/8oHN8zzsdiHBoinAiSXVUao=	OpenConcerto
quyA1TqAxXBg4XxJEZKIpZDMEZM=	OPENCONCERTO
yaKlVA3Pw+utmecjIjZ10/Fe3FQ=	abe
ROoFySfVpiQ6ibq6NMurlBpwCfY=	erp
3Hbp8MAAbo+RngxRXGbbujmC94U=	root
0DPiKuNIrrVmD8IUCuw1hQxNqZc=	admin
HYFBshX3RSTds6SiHVXMnCFBvQw=	Administrateur
wDiu3DInumStbeThJgoTeVWGxO8=	Indéfini
4xrK4RRtZEC3yqA9aapFyiGoc/M=	Indefini
W6ph5Mm5Pz8GgiULbPgzG37mj9g=	password
i+PJQ7Fgn/+/xRqtZm0KBK34PJ0=	Password
ESu3kTBHkd3PaS4p/VzxSbNf6jc=	PASSWORD
nU4eI71bcnBGqeO0t9tXvY1u5oQ=	pass
ANcMVhiSqUmAvv0SpADiautLhZk=	mdp
5en6G6MezRroT3XKqkdPOmY/BfQ=	secret
wLE3/i15JFnyb/djzORFdKW1qwM=	welcome
+pvrmeQCmtWmYVOZ57uuITVghrM=	changeme
nPldrNIm3PQ9o3bNtsu6cDUhiSE=	azerty
UgNuWpa0AUGeO4cLs4WYKLERr9I=	AZERTY
sbN3OgXA7QF2eHpPFXT/AHX3Uh4=	qwerty
cRDtpNCeBiql5KOQsKVyrA0sAiA=	1234
jLIjfQZ5yojbZGTqxg2pY0VROWQ=	12345
fEqNCco3Yq9h5ZUglD3CZJT4lBs=	123456
IOq+XWSw4hZ5boNPUtYf0LcDMvw=	1234567
fCIvspJ9goryL1khNOiTJIBjfA0=	12345678
98O8HYCOBHMq32eZZczDTKeuNEE=	123456789
yYSu0BSux2I6VPBZHaB6hf1Ldi0=	000000
PU8r8H3BvjiyDNbkaUmhBx+dDj0=	111111
3V/vnBwdoTlNbTSySMUb4q10CEA=	654321
SO/EhR4VlAr11HfTwM6ZIRpwo74=	1q2w3e4r
WK2YMTX+FcWo4uFftbUBrtz3DcI=	azertyuiop
lAwPJv1aMHdbscvR9oQDmNObuBM=	motdepasse
C5wmJdwh7wX2rU3fR8XyA4N6oyw=	toto
9+ecqOsLMe5NXWwYFBZmf/7lKO0=	titi
kHlaD/qouIwOJQVG2EObycMeWl4=	tata
Mqib3OwtUPncl0fNR+z8FM+cPb4=	tutu
qUqP5cyxm6YcTAhz05Hph5gvu9M=	test
Et6pb+wgWTVmq3VpLJlJWWgzrck=	user
NWdeaPS1r3uZXZIFrQ/EOELxZFA=	guest
Tyaur9sjZ2IKOTyXPt2+j4uEbr0=	master
Jzb6spHwTmm2LUkMPAk2H1uCRho=	login
KgmZjXL03C37IaINKFqdqy78Xws=	oc
w/+wOb5oqw0xy1ZCjko/XtwFKh4=	oc176
eqScpXsgGdf0HQa99HcHfu2e+AY=	OC176
p+a9cDQDWvLvJPUH6A0xi5J6/+M=	oc17
6JLTELe84lxcgXg9MshWcrB2W0s=	oc17.6
LV9F9KHtDr7id7cJ7Gok9Hmqrf8=	oc176p
0bUr073n6VqWySHWQc9tnkogrXU=	openconcerto176
3YQ4ToNZuowLswB0EPbL0Xg4EaI=	kinetic
OhrblYCjH/QEvkGGFNOGj3vaohE=	KINETIC
028dXtNzbQmBp+i3btM//f0EZz4=	Kinetic
zN/aofKdk/iUYF8HmW595jzQZgs=	therm
IMKroP3219juIhKHMMff8/qfjzw=	THERM
dJTzpTdbLaqp7qrxBCFGXfjM5m0=	therme
8gN47LVtluaRxp1VLiGkaXA02dE=	kinetictherm
1KXWmTXmP1BLATKkouX1MlkkS1c=	KineticTherm
h4uZM0NCo/F4rm2d8TG0AlCvuHs=	KINETICTHERM
3DOVIW5WIj2r+peUXh+MNBo9xmo=	kinetic-therm
G6FE8eEARUWL1XbRGAO2xzro3Ao=	kinetic42
AtlhT4dsigNRMT3a5OAl6MBx5s4=	k42
VxsBccpcbTCW1khxX1agrp4WM8E=	kt42
wejsAy7gFTo7ey9DM9N69vV9sME=	noon
/8oX/GJMPGwj29KRBc44nkB1fZ8=	Noon
+6UCuVNpFaDFyE3MhTw6tsQiQsw=	NOON
IICo6b56g+EaQJbZ4gKmib/s/O8=	ilm
2FVYkOQuinW/7Lu5WoBP4m6CYhc=	ILM
k4g2cu+Zch808qKvaXOUZpnNZx0=	ilminformatique
Pg1yLfpzZHJR0CPbkkj2ic3HjqQ=	jdc
ANsCd4GMMI0nhGgJmCCnqq5MtsI=	JDC
3qQRz1H8ER2XG+jtOEmfebudoHA=	jdc26
8PSl50r8RG2CWO51q2F1pBCCgp0=	entreprise
XIlMfLyGZTJ2aPC9quO62CWudcc=	societe
Vwd+mFBMiUj1z4/ehawJWBbd9BI=	direction
VjrY4o97S5I4cxaVtXA6UvJMnOE=	gisele
rEKE97i1ZDz6wsom+28CPIef5wQ=	Gisele
G8aMZj2kBd5qe9wtFWr5QuIrmT0=	GISÈLE
EzFynYHiUBA82lO8JSbZJYyf7Io=	gisèle
SQpqtfgUMxwIsEfHjxal1l358YY=	Gisèle
Qtvwd7UeQalJQoZ+DhyZRkhNwy8=	gizele
ZQmU3AqOZOq0Bzk0A++ttb5nkRE=	rebstock
H+JGJGhfeaImCKNRVXQUKPfvrfQ=	Rebstock
xJflOdvd6fomeJitpOmna9Pr7kQ=	REBSTOCK
Ox/jQNuna/NycKutd08yf1C14dg=	yves
JgHENXx0dpYYfn2gewFu4n1hha0=	Yves
2xW/095uZ5aIQaULPS5+D6xTXKE=	polsinelli
WO6M5XXkouZMGpTnL2OkdqRmUEY=	Polsinelli
HREECSB06uYPRB5+HyZZ6RmSam0=	POLSINELLI
lsJAznZNBzsVMUkpABLn7+C5EHg=	abe123
DealRL4EKKs0QJF+bBYybzfxIZ0=	erp123
WTOtoc3Vmtk9VrrChcTrFRU1p4M=	gise
MnfRFYuOe2d9luD28ABcMANanzc=	gigi
EJtcckbwh6pLXImQLrOGvGsNAlg=	loulou
RVu+4ZshHvMWGGpkeGJ6ca/REH4=	doudou
QY2UBkOxl11iI07gEkatS1iQQYQ=	nicolas
VGaVR6Il/yDLqLdaStylQO7yWFg=	martin
XGgsLR7EBz4nf5up9L3wfleU2r4=	julien
X1BEO/529yeajg8vCpiXXNv/OOk=	sophie
H9G0UWRzw2yPswu/fESQ/CBBmhA=	marine
/CeJovLzMD9zIu+lG7WIL+A0oyE=	caroline
tDsK0egQjnq4cNelT+rJOui4YA4=	julia
vo7CDVL98hwj6Duiu3RGp/7LMqw=	sarah
VfY6l67gXexXQoRnfrhoyDs/unw=	lea
jX086XfBXlvIVyenw8pe3+tUuCI=	manon
d4XbhFhbCfybxefnY/yhCVSIxEY=	chloe
/Y22by8F2bhzHHG6rO7FgiZaj6E=	ines
W9YPrtH32m0i3tlJkaVM0DYeaMs=	jade
DZYrGL9Id7lGZ+raEiSkmlkvfKY=	lucie
HO6lqvu2N8Y/Hy/9NeppGcvI2hQ=	lina
e3B0/KNvyJ+z8ePEbXT2/+JHegk=	rose
Ufix+ptCR0U3iCZydFKZfuKnw9c=	jean
LH+f0g++tBzoiU7EZT1m+n87bho=	michel
y7c1Pm2VPvNguvlgwSI0YnbG4yA=	patrick
u73ZBXGJxO5CK7k752Jch2n1kKs=	philippe
Nr1Pc74y7XJiwWTn7nIWPnVDmJ4=	stephane
cOi24TwY6IAO9rZxZtBAnmarWKk=	christine
LD3Gquhc61GgnTc/mrPH8yED/S8=	nathalie
QwP3+8dXY+MTO/dxT8kPAiYISLU=	isabelle
lcIZl+wS9sm7FfeMZHHG+sZ+w/8=	sylvie
8P1Zbzltj8MtXk/kxzxh+irFXHA=	marie
I+WR6MNt2ph5cGA60P3QMbff+fk=	france
PEvU0NDR4HbOYXcj7danOvyRJqs=	paris
RchYamJt2r0jOVEGYTjQ76f0650=	soleil
os6H3OuXRFCVVueADWtwx/u4KnY=	ete
dX4RwCJH6KK/r0E/JkjYz9Zc5tI=	hiver
4qxCz29Gg+AcwWn27gCnzsr0n/g=	printemps
OPXirRKXemEAVi3TaaumGu5YlFQ=	automne
hRmWwNyYGjNeBomlOwJDXm+PyOA=	vendredi
3iOtqmHxiPIPGe5jRZOhQwCMN6Q=	lundi
7w67t3KY4fvYH3VqTvw1uXfJPa4=	orange
lhQhpoHu6hxJ80pAQegC3PkmUa0=	citron
k+9d3kS1yx2PN5WYLukYxktxFPY=	banane
LSe2LFl+yFj257VOflhSXmqV5tg=	football
aCCN9lAbtfGgkYf3EAsu+PjZKHU=	rugby
FLEEaKMtvU0r6MmWkwlIgYyx69s=	chocolat
UveOyW9YY/m1bTJxKU6CpZuLvZs=	fromage
S4rWDbMgLl0KqRs935rwyJQHAws=	boulanger
DHYQpjWMEK9jWjUWlJVgDiXQLYM=	boulon
3KnxwB0t2M20mApZGY+U80zb5So=	picard
bmhJ44fLKGui7t5V5PvKowZ5LZk=	intersport
6uctVPdkTjb8zT3ouinbgQEkJE4=	decathlon
zzt0gREP/ATm8+sL/yRsImrk0MQ=	凭
rpFbhNSmSlSIGTjjOWOMEeZ3WP8=	KineticTherm42
6C9T19gek85YRMYZaHHliYhrM0A=	OpenConcerto176
0uSOxFKyIH/MJu9QOo6AwTAkdhk=	OpenConcerto1.7.6
7y3GSRvzoXV4NO9nYPReJPsgKbA=	OC1.7.6
aVbL/4b+Xi+jKQEqjcXrJynIJ/M=	OC-176
EoazwjcKptHoVjcST5AbYt0KTzQ=	oc-176
AbMHrLpPVPVar8M7sGu79sqAPpo=	1234567890
OwBKxtimAmgfXuNYfJJIVWeeIdk=	azerty123
o7R/496GkyKVPHDauCKj2TWeSS8=	motdepasse1
+GW1NiOxIf007lQmx5Llwzr4wic=	admin123
3ZRwlSi7HIPQjzCI1AQ/R0KJH08=	adminadmin
M6SFyxRuEVPGm1iMZxq0dPLluAA=	rootroot
Q1tBBo6GZVE6IAcMAzsIucZuQzI=	toor
fGphxo74ubawYbKMNIvB7Xkhy1M=	passw0rd
Ib0S3Bg/dA7nbye3jrOcitlyp1c=	P@ssw0rd
EH00i/9DfJman/GSrct4ywO43cY=	Azerty123
X2IOefbyinuCCoLVhd82bUGE9ZY=	soleil123
+gf1uufSiZQtDUfkg9TeEVMK4Os=	jaunesoleil
sDez63GbiJmAnn2HmL9kR2rBZ98=	vacances
95NAnRcub7gInNDccpO5NA/sWQI=	ete2026
a3GGOZqb/ic8dRV37z8XLOwSed4=	hiver2026
jDjR+hqu6v6+LjqMNzBiTqQeIwE=	noel2025
2Sl894ASwQLDma7m+K0N6ij4saA=	Kinetic-42
LvozhnAzS3tvVyNfO6mQB+4LIbY=	KT42
Vv1irx//SQNFmiZfArv/+LcS6Yc=	admin2026
ZEOO5CZDgWHaiFVLPi3nlrDKJl4=	changeme123
0xj0Rznc7WZ5OxpgMCgTOnauaA4=	Welcome1
LEkLjmi5LnnONEwl89h/wpfRI0Y=	Welcome123
6/x5EAd3cMg0D2PNLcoqwfEgRE8=	Passw0rd
dQXWSlTgYbes1UzNWLSdxDUAtjU=	default
CANDS
)

# ------------------------------------------------------------------ lecture
log "Utilisateurs de $BASE"
if [ -n "$LOGIN" ]; then
    ROWS=$(run_sql "select \"LOGIN\" || chr(9) || coalesce(\"PASSWORD\", '<null>') from \"Common\".\"USER_COMMON\" where \"LOGIN\" = '$LOGIN'")
else
    ROWS=$(run_sql "select \"LOGIN\" || chr(9) || coalesce(\"PASSWORD\", '<null>') from \"Common\".\"USER_COMMON\" order by \"ID\"")
fi
if [ -z "$ROWS" ]; then
    die "utilisateur introuvable : '$LOGIN'"
fi

FOUND_ANY=0
while IFS="$(printf '\t')" read -r USER HASH; do
    [ -n "$USER" ] || continue
    info "utilisateur $USER"
    if [ "$HASH" = "<null>" ]; then
        info "  mot de passe : NON DEFINI (connexion possible sans mot de passe ?)"
        continue
    fi
    # cas special OpenConcerto : hash du mot de passe vide => n'importe lequel
    EMPTY_HASH="2jmj7l5rSw0yVb/vlWAYkK/YBwk="
    if [ "$HASH" = "$EMPTY_HASH" ]; then
        info "  mot de passe : VIDE => N'IMPORTE QUEL mot de passe est accepte"
        FOUND_ANY=1
        continue
    fi
    MATCH=$(printf '%s\n' "$CANDIDATES" | awk -F'\t' -v h="$HASH" '$1 == h { print $2; exit }')
    if [ -n "$MATCH" ]; then
        info "  mot de passe TROUVE : $MATCH"
        FOUND_ANY=1
    else
        info "  hash : $HASH"
        info "  mot de passe : aucun candidat de la liste ne correspond"
    fi
done <<EOF
$ROWS
EOF

# ------------------------------------------------------------------ reset
if [ -n "$RESET" ]; then
    [ -n "$LOGIN" ] || die "--reset exige -U LOGIN"
    NEW_HASH=$(printf '%s' "$RESET" | sha1sum | cut -d' ' -f1)
    # OC : Base64(SHA1(mot de passe)) ; on reproduit l'encodage avec sha1sum+base64
    # tr -d '\n' : sans lui, le retour a la ligne de sha1sum s'ajoute au
    # binaire et le Base64 est faux (28 caracteres au lieu de 28 + '=').
    NEW_HASH_B64=$(printf '%s' "$RESET" | sha1sum | cut -d' ' -f1 | sed 's/../\\x&/g' | tr -d '\n' | xargs -0 printf '%b' | base64 -w0)
    log "Reinitialisation du mot de passe de $LOGIN"
    if [ "$DRY" = "1" ]; then
        info "ecrirait PASSWORD = $NEW_HASH_B64 pour $LOGIN"
    else
        run_sql "update \"Common\".\"USER_COMMON\" set \"PASSWORD\" = '$NEW_HASH_B64' where \"LOGIN\" = '$LOGIN'" >/dev/null
        info "mot de passe de $LOGIN redefini"
    fi
fi

if [ "$FOUND_ANY" = "0" ] && [ -z "$RESET" ]; then
    echo
    echo "  => Pour (re)definir le mot de passe :"
    echo "       bash $0 -U $LOGIN --reset nouveau_mot_de_passe"
fi
