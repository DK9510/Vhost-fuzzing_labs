#!/usr/bin/env bash
# c11 - silent front end: no SNI or no matching Host means no answer at all.
set -uo pipefail
LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$LAB_DIR/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/_shared/lib/check.sh"

PORT_HTTPS="${PORT_HTTPS:-18553}"
PORT_HTTP="${PORT_HTTP:-18190}"
H="https://${LAB_HOST:-127.0.0.1}:${PORT_HTTPS}"
P="http://${LAB_HOST:-127.0.0.1}:${PORT_HTTP}"
GOOD="ops.corp.lab"
T=4   # client-side timeout: silence must be observed, not waited out

# wait for the listener (a silent one accepts the TCP connection, so probe for a
# real answer on the allowed host instead of a status code from the bare IP)
for _ in $(seq 1 60); do
  [[ "$(curl -sk --max-time 3 -o /dev/null -w '%{http_code}' --resolve "$GOOD:${PORT_HTTPS}:${LAB_HOST:-127.0.0.1}" \
        https://$GOOD:${PORT_HTTPS}/ 2>/dev/null)" == "200" ]] && break
  sleep 1
done

echo "== c11 silent SNI/Host gate =="

# silence = curl exit 28 (timeout); 000 alone could also be a reset
hang() { # hang <label> <curl args...>
  local label="$1"; shift
  local rc=0 out
  out=$(curl -sk --max-time "$T" -o /dev/null -w '%{http_code}' "$@" 2>/dev/null) || rc=$?
  assert_eq "$label -> no response (timeout)" "28" "$rc"
  assert_eq "$label -> zero bytes of status" "000" "${out:-000}"
}

# 1. HTTPS with no SNI at all (curl sends no SNI for a bare IP)
hang "https://<ip> without SNI" "$H/"

# 2. HTTPS with the wrong SNI
hang "https://<ip> with SNI unknown.corp.lab" \
  --resolve "unknown.corp.lab:${PORT_HTTPS}:${LAB_HOST:-127.0.0.1}" "https://unknown.corp.lab:${PORT_HTTPS}/"

# 3. correct SNI, wrong Host: handshake completes, the request is dropped
hang "correct SNI, Host: chatadmin.corp.lab" \
  --resolve "$GOOD:${PORT_HTTPS}:${LAB_HOST:-127.0.0.1}" "https://$GOOD:${PORT_HTTPS}/" \
  -H 'Host: chatadmin.corp.lab'

# 4. plain HTTP straight at the IP (curl sends Host: <ip>:<port>)
hang "http://<ip> with no Host override" "$P/"

# 5. plain HTTP with the wrong Host
hang "http://<ip> Host: vpn.corp.lab" -H 'Host: vpn.corp.lab' "$P/"

# 6. HTTP/1.0 with an empty Host header
rc=0
curl -s --max-time "$T" -o /dev/null --http1.0 -H 'Host:' "$P/" 2>/dev/null || rc=$?
assert_eq "http with empty Host header -> no response" "28" "$rc"

# 7. the TLS layer never even says hello without SNI (no certificate, no alert)
out="$(timeout 6 openssl s_client -connect ${LAB_HOST:-127.0.0.1}:${PORT_HTTPS} </dev/null 2>/dev/null)"
assert_eq "no SNI -> no certificate offered" "0" "$(grep -c 'BEGIN CERTIFICATE' <<<"$out")"

# ---- and now the only way in: both names correct ----
CODE="$(curl -sk --max-time 6 -o /tmp/c11-index.html -w '%{http_code}' \
  --resolve "$GOOD:${PORT_HTTPS}:${LAB_HOST:-127.0.0.1}" "https://$GOOD:${PORT_HTTPS}/")"
assert_eq "SNI + Host both ops.corp.lab -> 200" "200" "$CODE"
assert_file_has "console page served" "Ops Console" /tmp/c11-index.html
assert_file_has "flag on the console page" "FLAG{" /tmp/c11-index.html

assert_header "front end identifies itself" Server "OpsGate/1.0" -k \
  --resolve "$GOOD:${PORT_HTTPS}:${LAB_HOST:-127.0.0.1}" "https://$GOOD:${PORT_HTTPS}/"

curl -sk --max-time 6 -H 'Host: ops.corp.lab' "$P/health" -o /tmp/c11-health.json
assert_file_has "health endpoint via plain HTTP + Host" '"status":"ok"' /tmp/c11-health.json

# Host with an explicit port still matches (port is stripped before comparison)
assert_eq "Host: ops.corp.lab:443 accepted" "200" \
  "$(curl -sk --max-time 6 -o /dev/null -w '%{http_code}' --resolve "$GOOD:${PORT_HTTPS}:${LAB_HOST:-127.0.0.1}" \
      "https://$GOOD:${PORT_HTTPS}/" -H "Host: $GOOD:443")"

# a trailing dot is NOT normalised away here: still silence
rc=0
curl -sk --max-time "$T" -o /dev/null --resolve "$GOOD:${PORT_HTTPS}:${LAB_HOST:-127.0.0.1}" \
  "https://$GOOD:${PORT_HTTPS}/" -H "Host: ${GOOD}." 2>/dev/null || rc=$?
assert_eq "Host with trailing dot -> silence" "28" "$rc"

# the certificate is still the lab wildcard (SNI selects it, Host does not)
assert_true "certificate is the wildcard leaf" bash -c \
  "openssl s_client -connect ${LAB_HOST:-127.0.0.1}:${PORT_HTTPS} -servername $GOOD </dev/null 2>/dev/null \
   | openssl x509 -noout -text | grep -q 'DNS:\*\.corp\.lab'"

summary
