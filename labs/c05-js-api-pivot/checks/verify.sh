#!/usr/bin/env bash
# c05 — bundle-driven pivot to the second vhost; 404 signatures as the discriminator.
set -uo pipefail
LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$LAB_DIR/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/_shared/lib/check.sh"

PORT_HTTPS="${PORT_HTTPS:-18483}"
H="https://${LAB_HOST:-127.0.0.1}:${PORT_HTTPS}"
SPA='Host: chatadmin.corp.lab'
API='Host: chat-api.corp.lab'

for _ in $(seq 1 40); do curl -sk -o /dev/null --max-time 1 "$H/" && break; sleep 0.25; done

echo "== c05 JS bundle -> API vhost =="

# 1. the SPA and its bundle
assert_code "SPA shell 200" 200 -k -H "$SPA" "$H/chatadmin"
assert_code "bundle 200"    200 -k -H "$SPA" "$H/chatadmin/assets/app.js"

# 2. the bundle names the backend, and the backend it names is the live one
BASE="$(curl -sk -H "$SPA" "$H/chatadmin/assets/app.js" | sed -n 's/.*API_BASE: *"\(https[^"]*\)".*/\1/p' | head -1)"
assert_eq "bundle API_BASE extracted" "https://chat-api.corp.lab/api" "$BASE"
API_HOST="$(printf '%s' "$BASE" | sed -E 's#https://([^/]+)/.*#\1#')"
assert_eq "API_BASE host" "chat-api.corp.lab" "$API_HOST"
assert_code "API_BASE /api/ is live" 200 -k -H "$API" "$H/api/"
assert_code "API_BASE /api/chat-status is live" 200 -k -H "$API" "$H/api/chat-status"
assert_body_has "API root lists the surface" "\"auth/password_reset\"" -k -H "$API" "$H/api/"

# 3. a URL in the bundle is not automatically a host: the staging pointer is a decoy
STAGE="$(curl -sk -H "$SPA" "$H/chatadmin/assets/app.js" | sed -n 's/.*STAGING_API: *"\(https[^"]*\)".*/\1/p' | head -1)"
assert_eq "decoy pointer extracted" "https://chat-staging.corp.lab/api" "$STAGE"
assert_code "decoy host does not exist -> 404" 404 -k -H 'Host: chat-staging.corp.lab' "$H/api/"

# 4. the signature comparison that tells you the API vhost is real
assert_header "api vhost 404 says Microsoft-IIS/10.0" Server "Microsoft-IIS/10.0" -k -H "$API" "$H/nope"
assert_header "bare IP 404 says Microsoft-HTTPAPI/2.0" Server "Microsoft-HTTPAPI/2.0" -k "$H/nope"
L_API="$(curl -sk -o /dev/null -w '%{size_download}' -H "$API" "$H/nope")"
L_BARE="$(curl -sk -o /dev/null -w '%{size_download}' "$H/nope")"
assert_ne "api 404 body differs from the bare-IP wall" "$L_API" "$L_BARE"
assert_eq "bare-IP wall is empty" "0" "$L_BARE"
assert_body_has "api 404 is the IIS error page" "404 - File or directory not found." -k -H "$API" "$H/nope"

# 5. the API vhost is not the SPA: same IP, different site
assert_body_lacks "api root is not the SPA shell" "Chat Admin —" -k -H "$API" "$H/api/"
assert_eq "api root is JSON" "application/json" \
  "$(curl -sk -D - -o /dev/null -H "$API" "$H/api/" | tr -d '\r' | awk -F': ' 'tolower($1)=="content-type"{print $2}')"

summary
