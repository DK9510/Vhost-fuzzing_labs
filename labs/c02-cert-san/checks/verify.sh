#!/usr/bin/env bash
# c02 — certificate names as a discovery source.
set -uo pipefail
LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$LAB_DIR/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/_shared/lib/check.sh"

PORT_HTTPS="${PORT_HTTPS:-18453}"
H="https://${LAB_HOST:-127.0.0.1}:${PORT_HTTPS}"
TLSX="${TLSX:-/Users/dk/.pdtm/go/bin/tlsx}"

for _ in $(seq 1 40); do curl -sk -o /dev/null --max-time 1 "$H/" && break; sleep 0.25; done

echo "== c02 certificate SAN/CN =="

# 1. openssl view: the cert itself names the sites (works everywhere)
SAN_TEXT="$(openssl s_client -connect "${LAB_HOST:-127.0.0.1}:${PORT_HTTPS}" -servername corp.lab </dev/null 2>/dev/null \
  | openssl x509 -noout -text 2>/dev/null | sed -n '/Subject Alternative Name/,+1p')"
SUBJ="$(printf '%s' "$SAN_TEXT" | grep -q 'DNS:\*\.corp\.lab' && echo wildcard || echo none)"
assert_true "openssl: SAN carries *.corp.lab" test "$SUBJ" = wildcard
assert_true "openssl: SAN carries the apex corp.lab" bash -c "printf '%s' '$SAN_TEXT' | grep -q 'DNS:corp.lab'"
assert_true "openssl: SAN carries mail.corp.lab (red herring)" bash -c "printf '%s' '$SAN_TEXT' | grep -q 'DNS:mail.corp.lab'"

# 2. the tool path the writeup uses
if [[ -x "$TLSX" ]]; then
  J="$("$TLSX" -u "${LAB_HOST:-127.0.0.1}:${PORT_HTTPS}" -san -cn -silent -json 2>/dev/null | head -1)"
  CN="$(printf '%s' "$J" | jq -r '.subject_cn // empty')"
  AN="$(printf '%s' "$J" | jq -r '.subject_an // [] | join(",")')"
  WC="$(printf '%s' "$J" | jq -r '.wildcard_certificate // false')"
  assert_eq "tlsx: subject_cn" "corp.lab" "$CN"
  assert_true "tlsx: SAN includes wildcard" bash -c "printf '%s' '$AN' | grep -q '\*\.corp\.lab'"
  assert_eq "tlsx: wildcard_certificate" "true" "$WC"
else
  echo "WARN  tlsx not found at $TLSX — openssl assertions only"
fi

# 3. a name in the certificate is not automatically a served site
assert_code "mail.corp.lab (cert name, no site) -> 404" 404 -k -H 'Host: mail.corp.lab' "$H/"
assert_code "apex corp.lab -> 200" 200 -k -H 'Host: corp.lab' "$H/"

# 4. wildcard cert != wildcard routing
assert_code "random subdomain of the wildcard -> 404" 404 -k -H 'Host: zzz.corp.lab' "$H/"
assert_header "random subdomain still HTTPAPI 404" Server "Microsoft-HTTPAPI/2.0" -k -H 'Host: zzz.corp.lab' "$H/"

# 5. with no SNI the default cert is still handed out (so passive cert grabs work)
SAN_NOSNI="$(openssl s_client -connect "${LAB_HOST:-127.0.0.1}:${PORT_HTTPS}" </dev/null 2>/dev/null \
  | openssl x509 -noout -text 2>/dev/null | sed -n '/Subject Alternative Name/,+1p')"
assert_true "no-SNI handshake returns the same cert names" bash -c "printf '%s' '$SAN_NOSNI' | grep -q '\*\.corp\.lab'"

summary
