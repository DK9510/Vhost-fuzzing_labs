#!/usr/bin/env bash
# c01 — bare-IP 404 fingerprint. Grades the observation, not a flag.
set -uo pipefail
LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$LAB_DIR/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/_shared/lib/check.sh"

PORT_HTTPS="${PORT_HTTPS:-18443}"
PORT_HTTP="${PORT_HTTP:-18080}"
H="https://${LAB_HOST:-127.0.0.1}:${PORT_HTTPS}"
P="http://${LAB_HOST:-127.0.0.1}:${PORT_HTTP}"

for _ in $(seq 1 40); do curl -sk -o /dev/null --max-time 1 "$H/" && break; sleep 0.25; done

echo "== c01 bare-IP 404 =="

# 1. bare IP is answered but not by an application
assert_code   "bare IP  -> 404"                 404 -k "$H/"
assert_header "bare IP  Server: Microsoft-HTTPAPI/2.0" Server "Microsoft-HTTPAPI/2.0" -k "$H/"
assert_header "bare IP  Content-Length: 0"      Content-Length "0" -k "$H/"
assert_no_header "bare IP  no X-Powered-By"     X-Powered-By -k "$H/"

# 2. same response on plain HTTP (fuzzers that do not speak TLS see the same wall)
assert_code   "bare IP over :80 -> 404"         404 "$P/"
assert_header "bare IP over :80 Server"         Server "Microsoft-HTTPAPI/2.0" "$P/"

# 3. the response is stable: this is a routing wall, not a random error
a="$(sha_of -k "$H/")"; b="$(sha_of -k "$H/")"; c="$(sha_of -k "$H/admin")"
assert_sha_same "bare IP body stable across requests" "$a" "$b"
assert_sha_same "bare IP body stable across paths"    "$a" "$c"

# 4. a valid hostname changes everything (the lesson of the case)
assert_code   "valid Host -> 200"                200 -k -H 'Host: ok.corp.lab' "$H/"
assert_header "valid Host Server: Microsoft-IIS/10.0" Server "Microsoft-IIS/10.0" -k -H 'Host: ok.corp.lab' "$H/"
assert_body_has "valid Host serves the IIS default page" "IIS Windows Server" -k -H 'Host: ok.corp.lab' "$H/"

# 5. no Host header at all (HTTP/1.0) still hits the wall
assert_code   "HTTP/1.0 without Host -> 404"     404 -k --http1.0 -H 'Host:' "$H/"

# 6. portal-style keyword routing is absent in this lab (keeps the case honest)
assert_code   "'portal' Host is still a 404 here" 404 -k -H 'Host: portal' "$H/"

summary
