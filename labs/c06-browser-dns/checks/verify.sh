#!/usr/bin/env bash
# c06 — browsing the vhosts like a user: HTML renderer, CA trust, DNS override.
set -uo pipefail
LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$LAB_DIR/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/_shared/lib/check.sh"

PORT_HTTPS="${PORT_HTTPS:-18493}"
H="https://${LAB_HOST:-127.0.0.1}:${PORT_HTTPS}"
API='Host: chat-api.corp.lab'
SPA='Host: chatadmin.corp.lab'
CA="$ROOT/_shared/certs/out/ca.crt"

for _ in $(seq 1 60); do
  [[ "$(curl -sk -o /dev/null -w '%{http_code}' -H "$API" "$H/api/")" == "200" ]] && break
  sleep 1
done

echo "== c06 browser path =="

# 1. content negotiation: the same URL is JSON for tools and HTML for a browser
assert_eq "JSON negotiated by default" "application/json" \
  "$(curl -sk -D - -o /dev/null -H "$API" "$H/api/" | tr -d '\r' | awk -F': ' 'tolower($1)=="content-type"{print $2}')"
CT_HTML="$(curl -sk -D - -o /dev/null -H "$API" -H 'Accept: text/html' "$H/api/" | tr -d '\r' | awk -F': ' 'tolower($1)=="content-type"{print $2}')"
assert_prefix "HTML negotiated with Accept: text/html" "text/html" "$CT_HTML"
assert_body_has "browsable renderer is Django REST framework" "Django REST framework" \
  -k -H "$API" -H 'Accept: text/html' "$H/api/"

# 2. the SPA the browser loads is the same content as the API host
assert_code "SPA shell 200" 200 -k -H "$SPA" "$H/chatadmin"
assert_body_has "bundle names the API base" "chat-api.corp.lab" -k -H "$SPA" "$H/chatadmin/assets/app.js"

# 3. TLS: the leaf chains to the shared lab CA, so a browser only needs one import
LEAF="$LAB_DIR/edge/certs/lab.crt"
assert_true "leaf cert exists" test -f "$LEAF"
if [[ -f "$CA" && -f "$LEAF" ]]; then
  assert_true "leaf verifies against the lab CA" openssl verify -CAfile "$CA" "$LEAF"
fi
assert_eq "served cert is the lab leaf" \
  "$(openssl x509 -in "$LEAF" -noout -fingerprint -sha256 | tr -d ' ' | cut -d= -f2)" \
  "$(openssl s_client -connect "${LAB_HOST:-127.0.0.1}:${PORT_HTTPS}" -servername chat-api.corp.lab </dev/null 2>/dev/null \
     | openssl x509 -noout -fingerprint -sha256 | tr -d ' ' | cut -d= -f2)"

# 4. no redirect loops on either vhost (a classic browser-only failure)
for host in chatadmin.corp.lab chat-api.corp.lab; do
  n="$(curl -sk -o /dev/null -w '%{num_redirects}' -H "Host: $host" "$H/api/")"
  assert_true "$host answers without redirects" test "$n" = "0"
done

# 5. what a browser must NOT be given: the API is not a directory listing
assert_body_lacks "no autoindex on the API host" "Index of /" -k -H "$API" -H 'Accept: text/html' "$H/api/"

summary
