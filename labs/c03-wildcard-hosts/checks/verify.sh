#!/usr/bin/env bash
# c03 — wildcard-driven Host header fuzzing with decoys.
set -uo pipefail
LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$LAB_DIR/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/_shared/lib/check.sh"

PORT_HTTPS="${PORT_HTTPS:-18463}"
H="https://${LAB_HOST:-127.0.0.1}:${PORT_HTTPS}"
WORDS="$ROOT/_shared/data/vhost-labels.txt"
DECOYS=(vpn intranet owa citrix sso webmail remote files sharepoint monitor)

for _ in $(seq 1 40); do curl -sk -o /dev/null --max-time 1 "$H/" && break; sleep 0.25; done

echo "== c03 wildcard host fuzzing =="

code() { curl -sk -o /dev/null -w '%{http_code}' -H "Host: $1" "$H$2"; }
body() { curl -sk -H "Host: $1" "$H$2"; }

# 1. all decoys look identical at the root: status alone is useless
base="$(sha_of -k -H 'Host: vpn.corp.lab' "$H/")"
same=1
for d in "${DECOYS[@]}"; do
  s="$(sha_of -k -H "Host: $d.corp.lab" "$H/")"
  [[ "$s" == "$base" ]] || same=0
done
assert_eq "10 decoy vhosts return byte-identical roots" "1" "$same"
assert_eq "real vhost root is the same default page too" "$base" "$(sha_of -k -H 'Host: chatadmin.corp.lab' "$H/")"
assert_eq "decoy root status" "200" "$(code vpn.corp.lab /)"

# 2. the discriminator: exactly one host in the wordlist exposes robots.txt
hits=0; hit_host=""
while read -r w; do
  [[ -z "$w" ]] && continue
  if [[ "$(code "$w.corp.lab" /robots.txt)" == "200" ]]; then hits=$((hits+1)); hit_host="$w.corp.lab"; fi
done < "$WORDS"
assert_eq "exactly one host serves /robots.txt" "1" "$hits"
assert_eq "that host is the planted vhost" "chatadmin.corp.lab" "$hit_host"
assert_body_has "robots.txt points at the app" "Disallow: /chatadmin" -k -H 'Host: chatadmin.corp.lab' "$H/robots.txt"

# 3. and exactly one host has the app directory
hits=0; hit_host=""
while read -r w; do
  [[ -z "$w" ]] && continue
  if [[ "$(code "$w.corp.lab" /chatadmin)" == "200" ]]; then hits=$((hits+1)); hit_host="$w.corp.lab"; fi
done < "$WORDS"
assert_eq "exactly one host serves /chatadmin" "1" "$hits"
assert_eq "same host for app path" "chatadmin.corp.lab" "$hit_host"

# 4. decoys dead-end on the app path, with the site's own 404 flavour
assert_eq "decoy /chatadmin -> 404" "404" "$(code vpn.corp.lab /chatadmin)"
assert_body_has "decoy 404 is the IIS error page" "404 - File or directory not found." \
  -k -H 'Host: vpn.corp.lab' "$H/chatadmin"

# 5. the baited host: 403 is not a win
assert_eq "old-portal -> 403" "403" "$(code old-portal.corp.lab /)"
assert_header "old-portal 403 comes from HTTPAPI, not a site" Server "Microsoft-HTTPAPI/2.0" \
  -k -H 'Host: old-portal.corp.lab' "$H/"

# 6. unknown host stays behind the wall
assert_eq "unlisted host -> 404" "404" "$(code nope.corp.lab /)"
assert_header "unlisted host is HTTPAPI" Server "Microsoft-HTTPAPI/2.0" -k -H 'Host: nope.corp.lab' "$H/"

# 7. IIS case-insensitivity applies to the matched site
assert_eq "app path is case-insensitive" "200" "$(code chatadmin.corp.lab /CHATADMIN)"
assert_eq "asset lookup is case-insensitive" "200" "$(code chatadmin.corp.lab /ChatAdmin/Index.HTML)"

# 8. optional: the same result through ffuf (the tool path in the writeup)
#    fuzz the app path, not the root: the root is deliberately identical on every vhost.
if command -v ffuf >/dev/null 2>&1; then
  out=/tmp/c03-ffuf.json
  ffuf -s -k -u "$H/chatadmin" -H 'Host: FUZZ.corp.lab' -w "$WORDS" -fc 403,404 -timeout 5 \
      -o "$out" -of json >/dev/null 2>&1 || true
  n="$(jq -r '[.results[] | select(.status==200)] | length' "$out" 2>/dev/null || echo 0)"
  assert_eq "ffuf: exactly one 200 on /chatadmin" "1" "$n"
  host="$(jq -r '[.results[] | select(.status==200)][0].input.FUZZ // empty' "$out" 2>/dev/null || true)"
  assert_eq "ffuf: the hit is chatadmin" "chatadmin" "$host"
else
  echo "WARN  ffuf not installed — tool-parity assertion skipped"
fi

summary
