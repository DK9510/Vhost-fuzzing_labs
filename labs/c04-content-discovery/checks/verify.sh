#!/usr/bin/env bash
# c04 — active content discovery on an IIS default page.
set -uo pipefail
LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$LAB_DIR/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/_shared/lib/check.sh"

PORT_HTTPS="${PORT_HTTPS:-18473}"
H="https://${LAB_HOST:-127.0.0.1}:${PORT_HTTPS}"
HOSTHDR='Host: chatadmin.corp.lab'
WORDS="${WORDS:-/Users/dk/tools/wordlists/SecLists/Discovery/Web-Content/raft-large-directories-lowercase.txt}"

for _ in $(seq 1 40); do curl -sk -o /dev/null --max-time 1 "$H/" && break; sleep 0.25; done

echo "== c04 content discovery =="

st() { curl -sk -o /dev/null -w '%{http_code}' -H "$HOSTHDR" "$H$1"; }
len() { curl -sk -o /dev/null -w '%{size_download}' -H "$HOSTHDR" "$H$1"; }

# 1. the site is a default page: nothing to crawl, so discovery must be active
assert_eq   "root is the IIS default page" "200" "$(st /)"
assert_body_has "root carries the default-page marker" "IIS Windows Server" -k -H "$HOSTHDR" "$H/"

# 2. 404 baseline is a real page, so size filtering is meaningful
assert_eq "missing path -> 404"             "404" "$(st /definitely-not-here)"
assert_eq "missing path body is the IIS 404 page" "1232" "$(len /definitely-not-here)"
assert_body_has "404 body text"             "404 - File or directory not found." -k -H "$HOSTHDR" "$H/definitely-not-here"

# 3. the planted directory
assert_eq   "/chatadmin -> 200"             "200" "$(st /chatadmin)"
assert_eq   "/chatadmin/ -> 200"            "200" "$(st /chatadmin/)"
assert_body_has "app shell is served"       "Chat Admin" -k -H "$HOSTHDR" "$H/chatadmin"
assert_body_lacks "no directory listing"    "Index of /" -k -H "$HOSTHDR" "$H/chatadmin/"

# 4. IIS semantics: path lookup is case-insensitive
assert_eq   "/CHATADMIN -> 200"             "200" "$(st /CHATADMIN)"
assert_eq   "/ChatAdmin/ -> 200"            "200" "$(st /ChatAdmin/)"

# 5. bait: a backup tree exists but is refused — a 403 is not a win
assert_eq   "/chatadmin.backup -> 403"      "403" "$(st /chatadmin.backup)"

# 6. assets referenced by the shell are reachable
assert_eq   "bundle is served"              "200" "$(st /chatadmin/assets/app.js)"
assert_body_has "bundle names the API base" "chat-api.corp.lab" -k -H "$HOSTHDR" "$H/chatadmin/assets/app.js"

# 7. the writeup's wordlist finds it (and only it)
if [[ -r "$WORDS" ]] && command -v ffuf >/dev/null 2>&1; then
  out=/tmp/c04-ffuf.json; base="$(len /definitely-not-here)"
  ffuf -s -k -u "$H/FUZZ" -H "$HOSTHDR" -w "$WORDS" -fs "$base" -fc 403 -t 40 \
      -timeout 10 -o "$out" -of json >/tmp/c04-ffuf.out 2>&1 || true
  hits="$(jq -r '[.results[] | select(.status==200) | .input.FUZZ] | join(",")' "$out" 2>/dev/null || true)"
  assert_eq "raft wordlist finds exactly /chatadmin" "chatadmin" "$hits"
else
  echo "WARN  raft wordlist or ffuf unavailable — discovery assertion skipped"
fi

summary
