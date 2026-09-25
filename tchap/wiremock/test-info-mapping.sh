#!/bin/bash
#
# Tests du mapping WireMock fusionné "Internal Info Mapping"
# (tchap/wiremock/mappings/internal-info-mapping.json)
#
# Ce mapping remplace les 4 anciens fichiers :
#   - user-mapping-internal.json
#   - invited-mapping-internal.json
#   - not-invited-mapping-internal.json
#   - wrong-hs-mapping-internal.json
#
# Il vérifie le comportement de :
#   GET /_matrix/identity/api/v1/internal-info?medium=email&address=<adresse>
#
#   - domaine agent (@tchapgouv.com, @numerique.gouv.fr, @beta.gouv.fr,
#     @tchap.incubateur.net)  -> hs=tchapgouv.com, requires_invite=false, invited=false
#   - @invited.externe.com     -> hs=tchapgouv.com, requires_invite=true,  invited=true
#   - @not.invited.externe.com -> hs=tchapgouv.com, requires_invite=true,  invited=false
#   - toute autre adresse (fallback) -> hs=wrong.server.com, requires_invite=false, invited=false
#   - paramètre address absent, ou medium != email -> 404
#
# Usage :
#   ./test-internal-info-mapping.sh [BASE_URL]
#
#   BASE_URL par défaut : http://localhost:${IDENTITY_MOCK_PORT:-8083}
#   (IDENTITY_MOCK_PORT est la variable du compose-tchap-additional-services.yml,
#    service identity-mock)

set -u

BASE_URL="${1:-http://localhost:${IDENTITY_MOCK_PORT:-8083}}"
ENDPOINT="${BASE_URL}/_matrix/identity/api/v1/info"

PASS=0
FAIL=0

# Couleurs (désactivées si la sortie n'est pas un terminal)
if [ -t 1 ]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  RESET='\033[0m'
else
  GREEN=''
  RED=''
  RESET=''
fi

pass() { PASS=$((PASS + 1)); printf "${GREEN}[PASS]${RESET} %s\n" "$1"; }
fail() { FAIL=$((FAIL + 1)); printf "${RED}[FAIL]${RESET} %s\n" "$1"; }

# Canonise un JSON (clés triées) pour une comparaison indépendante de l'ordre
json_canon() {
  python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin), sort_keys=True))' 2>/dev/null
}

# Attend que le mock soit joignable avant de lancer les tests
wait_for_wiremock() {
  local i
  for i in $(seq 1 30); do
    curl -s --max-time 2 -o /dev/null "${BASE_URL}/__admin/health" && return 0
    sleep 1
  done
  return 1
}

# expect_body <description> <url> <json attendu>
#   Compare le corps de la réponse au JSON attendu (après canonisation)
expect_body() {
  local desc="$1" url="$2" expected="$3"
  local actual canon_expected

  actual=$(curl -s --max-time 5 "$url" | json_canon)
  canon_expected=$(printf '%s' "$expected" | json_canon)

  if [ "$actual" = "$canon_expected" ]; then
    pass "$desc"
  else
    fail "$desc"
    echo "         attendu : $canon_expected"
    echo "         obtenu  : ${actual:-<réponse vide ou non JSON>}"
  fi
}

# expect_status <description> <url> <code HTTP attendu>
expect_status() {
  local desc="$1" url="$2" expected="$3"
  local actual

  actual=$(curl -s --max-time 5 -o /dev/null -w '%{http_code}' "$url")

  if [ "$actual" = "$expected" ]; then
    pass "$desc"
  else
    fail "$desc"
    echo "         statut attendu : $expected, obtenu : $actual"
  fi
}

# expect_header <description> <url> <header> <valeur attendue (motif grep)>
expect_header() {
  local desc="$1" url="$2" header="$3" value="$4"
  local actual

  actual=$(curl -s --max-time 5 -o /dev/null -D - "$url" | tr -d '\r' | grep -i "^${header}: *${value}$")

  if [ -n "$actual" ]; then
    pass "$desc"
  else
    fail "$desc"
    echo "         header attendu : ${header}: ${value}"
  fi
}

# --- Pré-requis ----------------------------------------------------------------

command -v curl >/dev/null 2>&1 || { echo "curl est requis" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 est requis" >&2; exit 2; }

if ! wait_for_wiremock; then
  echo "WireMock injoignable sur ${BASE_URL}" >&2
  echo "(service identity-mock, voir compose-tchap-additional-services.yml)" >&2
  exit 2
fi
printf "WireMock joignable sur %s\n\n" "$BASE_URL"

# --- Réponses attendues --------------------------------------------------------

AGENT='{"hs":"tchapgouv.com"}'
INVITED='{"hs":"tchapgouv.com"}'
NOT_INVITED='{"hs":"tchapgouv.com"}'
FALLBACK='{"hs":"wrong.server.com"}'

# --- Tests : domaines agents ----------------------------------------------------

expect_body "agent tchapgouv.com               -> hs=tchapgouv.com, invited=false" \
  "${ENDPOINT}?medium=email&address=user%@tchapgouv.com" "$AGENT"

expect_body "agent numerique.gouv.fr           -> hs=tchapgouv.com, invited=false" \
  "${ENDPOINT}?medium=email&address=user%40numerique.gouv.fr" "$AGENT"

expect_body "agent beta.gouv.fr                -> hs=tchapgouv.com, invited=false" \
  "${ENDPOINT}?medium=email&address=user%40beta.gouv.fr" "$AGENT"

expect_body "agent tchap.incubateur.net        -> hs=tchapgouv.com, invited=false" \
  "${ENDPOINT}?medium=email&address=user%40tchap.incubateur.net" "$AGENT"

# --- Tests : utilisateurs externes ----------------------------------------------

expect_body "invited.externe.com               -> hs=tchapgouv.com, invited=true" \
  "${ENDPOINT}?medium=email&address=user%40invited.externe.com" "$INVITED"

expect_body "not.invited.externe.com           -> hs=tchapgouv.com, invited=false" \
  "${ENDPOINT}?medium=email&address=user%40not.invited.externe.com" "$NOT_INVITED"

# --- Tests : fallback ------------------------------------------------------------

expect_body "wrong.server.com                  -> hs=wrong.server.com (fallback)" \
  "${ENDPOINT}?medium=email&address=user%40wrong.server.com" "$FALLBACK"

expect_body "adresse inconnue                  -> hs=wrong.server.com (fallback)" \
  "${ENDPOINT}?medium=email&address=user%40inconnu.example.org" "$FALLBACK"

expect_body "adresse vide                      -> hs=wrong.server.com (fallback)" \
  "${ENDPOINT}?medium=email&address=" "$FALLBACK"

# --- Tests : encodage de l'adresse ----------------------------------------------

expect_body "@ non encodé, invited             -> hs=tchapgouv.com, invited=true" \
  "${ENDPOINT}?medium=email&address=user@invited.externe.com" "$INVITED"

expect_body "@ non encodé, adresse inconnue    -> hs=wrong.server.com (fallback)" \
  "${ENDPOINT}?medium=email&address=user@inconnu.example.org" "$FALLBACK"

# --- Tests : cas d'erreur (404) --------------------------------------------------

expect_status "sans paramètre address           -> 404" \
  "${ENDPOINT}?medium=email" "404"

expect_status "medium != email                  -> 404" \
  "${ENDPOINT}?medium=sms&address=user%40tchapgouv.com" "404"

# --- Tests : headers --------------------------------------------------------------

expect_header "header Content-Type              -> application/json" \
  "${ENDPOINT}?medium=email&address=user%40tchapgouv.com" "Content-Type" "application/json"

expect_header "header Access-Control-Allow-Origin -> *" \
  "${ENDPOINT}?medium=email&address=user%40tchapgouv.com" "Access-Control-Allow-Origin" '\*'

# --- Bilan ------------------------------------------------------------------------

printf "\n"
if [ "$FAIL" -eq 0 ]; then
  printf "${GREEN}OK${RESET} : %d test(s) passé(s), 0 échec\n" "$PASS"
  exit 0
else
  printf "${RED}KO${RESET} : %d test(s) passé(s), %d échoué(s)\n" "$PASS" "$FAIL"
  exit 1
fi
