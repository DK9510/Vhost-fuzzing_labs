#!/usr/bin/env bash
# c09 — 40 vhosts, 1 real. Precision, not recall: no false positives allowed.
set -uo pipefail
LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$LAB_DIR/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/_shared/lib/check.sh"

PORT_HTTPS="${PORT_HTTPS:-18523}"
H="https://${LAB_HOST:-127.0.0.1}:${PORT_HTTPS}"
NAMES=/tmp/c09-names.txt
REAL=chatadmin.corp.lab
CATCHALLS="monitor status"
LURES="vpn intranet owa citrix sso webmail remote files"

for _ in $(seq 1 40); do curl -sk -o /dev/null --max-time 1 "$H/" && break; sleep 0.25; done

echo "== c09 decoy discipline =="

jq -r '.sites[].host' "$LAB_DIR/edge/sites.json" | sort > "$NAMES"
assert_eq "40 vhosts configured" "40" "$(wc -l < "$NAMES" | tr -d ' ')"

code() { curl -sk -o /dev/null -w '%{http_code}' -H "Host: $1" "$H$2"; }
body() { curl -sk -H "Host: $1" "$H$2"; }

# 1. the real site: robots.txt + an app that identifies itself
assert_eq "real host /robots.txt 200"      "200" "$(code $REAL /robots.txt)"
assert_eq "real host /app 200"             "200" "$(code $REAL /app)"
assert_body_has "real app has the marker"  "Chat Admin" -k -H "Host: $REAL" "$H/app"

# 2. one sweep, scored strictly: a hit needs the app marker, not just a 200
hits=""; false_pos=0
while read -r host; do
  [[ -z "$host" ]] && continue
  [[ "$(code "$host" /app)" == "200" ]] || continue
  if [[ "$(body "$host" /app)" == *"Chat Admin"* ]]; then
    hits="$hits $host"
  else
    false_pos=$((false_pos + 1))
  fi
done < "$NAMES"
assert_eq "exactly one true hit among 40 hosts" "1" "$(echo $hits | wc -w | tr -d ' ')"
assert_eq "the hit is the planted host" "$REAL" "$(echo $hits | xargs)"

# 3. the traps that produce false positives
assert_true "catch-all decoys answer 200 on /app (>=2)" test "$false_pos" -ge 2
for c in $CATCHALLS; do
  assert_eq "catch-all decoy $c.corp.lab returns 200 on /app" "200" "$(code $c.corp.lab /app)"
  assert_eq "catch-all $c body has no app marker" "0" "$(body "$c.corp.lab" /app | grep -c 'Chat Admin' || true)"
done

# 4. the lures: response headers claim the real host, the body says otherwise
lured=0
lured_hits=0
for l in $LURES; do
  hdr="$(curl -sk -D - -o /dev/null -H "Host: $l.corp.lab" "$H/" | tr -d '\r' \
        | awk -F': ' 'tolower($1)=="x-forwarded-host"{print $2}')"
  [[ "$hdr" == "$REAL" ]] && lured=$((lured + 1))
  case "$(body "$l.corp.lab" /app)" in *"Chat Admin"*) lured_hits=$((lured_hits + 1));; esac
done
assert_eq "8 decoys echo X-Forwarded-Host" "8" "$lured"
assert_eq "none of the lures carry the app" "0" "$lured_hits"

# 5. every decoy root is byte-identical: length/status triage alone cannot separate them
first=""; same=1
while read -r host; do
  [[ "$host" == "$REAL" ]] && continue
  s="$(sha_of -k -H "Host: $host" "$H/")"
  [[ -z "$first" ]] && first="$s"
  [[ "$s" == "$first" ]] || same=0
done < "$NAMES"
assert_eq "39 decoy roots are byte-identical" "1" "$same"

# 6. unknown hosts stay behind the wall
assert_code "unlisted host -> 404" 404 -k -H 'Host: not-in-scope.corp.lab' "$H/"

summary
