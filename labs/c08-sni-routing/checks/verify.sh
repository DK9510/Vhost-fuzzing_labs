#!/usr/bin/env bash
# c08 — SNI vs Host: two certificates on one listener, routing decided by Host.
set -uo pipefail
LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$LAB_DIR/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/_shared/lib/check.sh"

PORT_HTTPS="${PORT_HTTPS:-18513}"
H="https://${LAB_HOST:-127.0.0.1}:${PORT_HTTPS}"
CERTS="$LAB_DIR/edge/certs"

for _ in $(seq 1 40); do curl -sk -o /dev/null --max-time 1 "$H/" && break; sleep 0.25; done

echo "== c08 SNI vs Host =="

fp_file() { openssl x509 -in "$1" -noout -fingerprint -sha256 | tr -d ' ' | cut -d= -f2; }
fp_sni() {
  openssl s_client -connect "${LAB_HOST:-127.0.0.1}:${PORT_HTTPS}" -servername "$1" </dev/null 2>/dev/null \
    | openssl x509 -noout -fingerprint -sha256 | tr -d ' ' | cut -d= -f2
}
san_sni() {
  openssl s_client -connect "${LAB_HOST:-127.0.0.1}:${PORT_HTTPS}" -servername "$1" </dev/null 2>/dev/null \
    | openssl x509 -noout -text 2>/dev/null | sed -n '/Subject Alternative Name/,+1p'
}

FP_DEFAULT="$(fp_file "$CERTS/lab.crt")"
FP_INTERNAL="$(fp_file "$CERTS/internal.crt")"
assert_ne "two different certs exist" "$FP_DEFAULT" "$FP_INTERNAL"

# 1. SNI selects the certificate
assert_eq "SNI corp.lab -> default cert" "$FP_DEFAULT" "$(fp_sni corp.lab)"
assert_eq "SNI internal.corp.lab -> internal cert" "$FP_INTERNAL" "$(fp_sni internal.corp.lab)"
assert_eq "unknown SNI falls back to the default cert" "$FP_DEFAULT" "$(fp_sni nothing.corp.lab)"

# 2. the internal cert names the internal zone only
SAN_INT="$(san_sni internal.corp.lab)"
assert_true "internal cert carries *.internal.corp.lab" bash -c "printf '%s' '$SAN_INT' | grep -q 'internal.corp.lab'"
assert_true "internal cert does not carry the public apex" bash -c "! printf '%s' '$SAN_INT' | grep -q 'DNS:corp.lab'"

# 3. routing is by Host header, not by SNI (a client can present the public cert and
#    still reach the internal vhost)
assert_eq "Host app.corp.lab -> 200" "200" \
  "$(curl -sk -o /dev/null -w '%{http_code}' -H 'Host: app.corp.lab' "$H/")"
assert_eq "Host admin.internal.corp.lab -> 200 (public SNI)" "200" \
  "$(curl -sk -o /dev/null -w '%{http_code}' -H 'Host: admin.internal.corp.lab' "$H/")"
assert_body_has "internal app body served" "Internal Admin" -k -H 'Host: admin.internal.corp.lab' "$H/"

# 4. ...and the reverse: the internal cert does not unlock anything by itself
assert_eq "internal SNI + public Host -> 200" "200" \
  "$(curl -sk -o /dev/null -w '%{http_code}' --resolve app.corp.lab:"${PORT_HTTPS}":${LAB_HOST:-127.0.0.1} \
      "https://app.corp.lab:${PORT_HTTPS}/")"

# 5. so the lesson: mismatch is a certificate warning, not an access control
MISMATCH="$(openssl s_client -connect "${LAB_HOST:-127.0.0.1}:${PORT_HTTPS}" -servername corp.lab </dev/null 2>/dev/null \
  | openssl x509 -noout -text 2>/dev/null | sed -n '/Subject Alternative Name/,+1p')"
assert_true "public SNI cert does not mention internal zone" bash -c "! printf '%s' '$MISMATCH' | grep -q 'internal.corp.lab'"

summary
