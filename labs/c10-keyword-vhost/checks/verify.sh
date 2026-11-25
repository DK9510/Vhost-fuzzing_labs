#!/usr/bin/env bash
# c10 — keyword-matched vhost: a word in the Host header, in any domain shape.
set -uo pipefail
LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$LAB_DIR/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/_shared/lib/check.sh"

PORT_HTTPS="${PORT_HTTPS:-18533}"
PORT_HTTP="${PORT_HTTP:-18170}"
H="https://${LAB_HOST:-127.0.0.1}:${PORT_HTTPS}"
P="http://${LAB_HOST:-127.0.0.1}:${PORT_HTTP}"
WORDS="$ROOT/_shared/data/host-keywords.txt"
ALLOWED_PASS="${ALLOWED_PASS:-agent-pass-2026}"

for _ in $(seq 1 60); do
  [[ "$(curl -sk -o /dev/null -w '%{http_code}' -H 'Host: portal' "$H/")" == "200" ]] && break
  sleep 1
done

echo "== c10 keyword vhost =="

code() { curl -sk -o /dev/null -w '%{http_code}' -H "Host: $1" "$H${2:-/}"; }
body() { curl -sk -H "Host: $1" "$H${2:-/}"; }

# 1. every documented shape reaches the same app
REF="$(sha_of -k -H 'Host: portal' "$H/")"
assert_eq "Host: portal -> 200"            "200" "$(code portal)"
assert_header "portal app identifies itself" X-App "portal" -k -H 'Host: portal' "$H/"
assert_body_has "portal landing page"      "<h1>Portal</h1>" -k -H 'Host: portal' "$H/"
assert_sha_same "portalstg.app.test same app" "$REF" "$(sha_of -k -H 'Host: portalstg.app.test' "$H/")"
assert_sha_same "app.portal.test same app"    "$REF" "$(sha_of -k -H 'Host: app.portal.test' "$H/")"
assert_sha_same "chat.portal.corp.lab same app" "$REF" "$(sha_of -k -H 'Host: chat.portal.corp.lab' "$H/")"
assert_eq "Host: PORTAL (case) -> 200"     "200" "$(code PORTAL)"
assert_eq "Host: portal:443 (port) -> 200" "200" "$(code portal:443)"

# 2. no domain allowlist: a hostname the attacker controls reaches the app
assert_eq "Host: portal.attacker.test -> 200" "200" "$(code portal.attacker.test)"
assert_sha_same "attacker domain gets the same app" "$REF" \
  "$(sha_of -k -H 'Host: portal.attacker.test' "$H/")"

# 3. the trailing-dot gap: the suffix rule wins, and it does not serve the app
assert_eq "Host: portal. (trailing dot) -> 404" "404" "$(code 'portal.')"
assert_header "trailing-dot answer is the HTTPAPI wall" Server "Microsoft-HTTPAPI/2.0" -k -H 'Host: portal.' "$H/"

# 4. precedence: exact hostname rules beat keyword rules
assert_eq "exact vhost still served" "200" "$(code chatadmin.corp.lab /chatadmin)"
assert_body_has "exact vhost is the SPA, not the portal" "Chat Admin" -k -H 'Host: chatadmin.corp.lab' "$H/chatadmin"

# 5. bait: a keyword route that answers 403 is not a win
assert_eq "Host: vpn.corp.lab -> 403 (bait)" "403" "$(code vpn.corp.lab)"

# 6. HTTP/1.0 without any Host still hits the wall
assert_eq "no Host header -> 404" "404" "$(curl -sk -o /dev/null -w '%{http_code}' --http1.0 -H 'Host:' "$H/")"

# 7. plain HTTP behaves identically (many sweeps run on :80)
assert_eq "portal over :80 -> 200" "200" \
  "$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: portal' "$P/")"

# 8. the keyword is a route, not a login: the dashboard is still gated
ANON="$(curl -sk -o /dev/null -w '%{http_code}' -H 'Host: portal' "$H/dashboard")"
assert_true "dashboard refused anonymously (401/403)" test "$ANON" = "401" -o "$ANON" = "403"
TOK="$(curl -sk -H 'Host: portal' -H 'Content-Type: application/json' \
  -d "{\"email\":\"alex@corp.lab\",\"password\":\"$ALLOWED_PASS\"}" "$H/api/auth/login" | jq -r '.token // empty')"
assert_ne "agent login through the keyword route returns a token" "" "$TOK"
assert_eq "dashboard with a token -> 200" "200" \
  "$(curl -sk -o /dev/null -w '%{http_code}' -H 'Host: portal' -H "Authorization: Bearer $TOK" "$H/dashboard")"

# 9. the sweep script must find the keyword family and stay quiet about everything else
if [[ -x "$ROOT/scripts/keyword-sweep.sh" ]]; then
  OUT=/tmp/c10-sweep.jsonl bash "$ROOT/scripts/keyword-sweep.sh" "$H" "$WORDS" corp.lab >/tmp/c10-sweep.log 2>&1 || true
  flagged="$(jq -r 'select(.hit) | .word' /tmp/c10-sweep.jsonl 2>/dev/null | sort -u)"
  expect="$(grep -c 'portal' "$WORDS")"
  assert_eq "sweep flags the portal family + the vpn bait" "$((expect + 1))" "$(echo "$flagged" | grep -c . || true)"
  assert_true "sweep flags the bare keyword" grep -qx 'portal' <<<"$flagged"
  assert_true "the 403 bait is flagged too (an anomaly is an anomaly)" grep -qx 'vpn' <<<"$flagged"
  assert_eq "vpn anomaly is a 403, not an app" "403" \
    "$(jq -r 'select(.word=="vpn" and .shape=="bare") | .status' /tmp/c10-sweep.jsonl)"
  assert_eq "no word outside the keyword family is flagged" "0" \
    "$(echo "$flagged" | grep -Ev 'portal|^vpn$' | grep -c . || true)"
  assert_true "sweep records >=2 agreeing shapes for 'portal'" \
    test "$(jq -r 'select(.word=="portal" and .hit) | .shape' /tmp/c10-sweep.jsonl | wc -l | tr -d ' ')" -ge 2
else
  echo "WARN  keyword-sweep.sh not executable — sweep assertion skipped"
fi

summary
