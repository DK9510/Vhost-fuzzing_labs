# shellcheck shell=bash
# vhostlab check helpers. Source this file, call asserts, end with summary.
# Every assert takes <label> <expected> then a full curl argument list ending in the URL,
# e.g.  assert_code "bare ip 404" 404 -k https://127.0.0.1:18443/
#
# LAB_HOST selects which address the labs are exercised on: unset/127.0.0.1 grades the
# host-local path, LAB_HOST=10.10.1.9 grades the same assertions over the LAN path.
LAB_HOST="${LAB_HOST:-127.0.0.1}"; export LAB_HOST
FAILS=0
PASSES=0

pass() { printf 'PASS  %s\n' "$1"; PASSES=$((PASSES + 1)); }
fail() { printf 'FAIL  %s :: %s\n' "$1" "${2:-}"; FAILS=$((FAILS + 1)); }

_curl() { curl -sk --max-time 10 "$@"; }

assert_code() {
  local label="$1" want="$2"; shift 2
  local got; got="$(_curl -o /dev/null -w '%{http_code}' "$@")"
  if [[ "$got" == "$want" ]]; then pass "$label"; else fail "$label" "want=$want got=$got"; fi
}

assert_header() {
  local label="$1" header="$2" want="$3"; shift 3
  local raw got
  raw="$(_curl -D - -o /dev/null "$@" | tr -d '\r')"
  got="$(printf '%s\n' "$raw" | awk -F': ' -v h="$header" 'tolower($1)==tolower(h){print $2; exit}')"
  if [[ "$got" == "$want" ]]; then pass "$label"; else fail "$label" "want '$header: $want' got '${got:-<absent>}'"; fi
}

assert_no_header() {
  local label="$1" header="$2"; shift 2
  local raw
  raw="$(_curl -D - -o /dev/null "$@" | tr -d '\r')"
  if printf '%s\n' "$raw" | awk -F': ' -v h="$header" 'tolower($1)==tolower(h){found=1} END{exit !found}'; then
    fail "$label" "unexpected header $header present"
  else
    pass "$label"
  fi
}

assert_body_has() {
  local label="$1" needle="$2"; shift 2
  local body; body="$(_curl "$@")"
  if [[ "$body" == *"$needle"* ]]; then pass "$label"; else fail "$label" "body missing '$needle'"; fi
}

assert_body_lacks() {
  local label="$1" needle="$2"; shift 2
  local body; body="$(_curl "$@")"
  if [[ "$body" != *"$needle"* ]]; then pass "$label"; else fail "$label" "body unexpectedly contains '$needle'"; fi
}

sha_of() { _curl "$@" | shasum -a 1 | awk '{print $1}'; }

assert_sha_same() {
  local label="$1" a="$2" b="$3"
  if [[ "$a" == "$b" ]]; then pass "$label"; else fail "$label" "sha mismatch ${a:0:12} vs ${b:0:12}"; fi
}

assert_sha_diff() {
  local label="$1" a="$2" b="$3"
  if [[ "$a" != "$b" ]]; then pass "$label"; else fail "$label" "bodies identical (${a:0:12})"; fi
}

assert_true() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$label"; else fail "$label" "command failed: $*"; fi
}

# file-based variants: use these when the assertion is about a response you already saved
# (a POST result, a 500 page) instead of a fresh GET.
assert_file_has() {
  local label="$1" needle="$2" file="$3"
  if grep -qF -- "$needle" "$file" 2>/dev/null; then pass "$label"; else fail "$label" "'$needle' not in $file"; fi
}

assert_file_lacks() {
  local label="$1" needle="$2" file="$3"
  if grep -qF -- "$needle" "$file" 2>/dev/null; then fail "$label" "'$needle' unexpectedly in $file"; else pass "$label"; fi
}

assert_file_size_gt() {
  local label="$1" min="$2" file="$3" size
  size="$(wc -c < "$file" | tr -d ' ')"
  if [[ "$size" -gt "$min" ]]; then pass "$label"; else fail "$label" "size=$size want>$min"; fi
}

assert_eq() {
  local label="$1" want="$2" got="$3"
  if [[ "$got" == "$want" ]]; then pass "$label"; else fail "$label" "want=$want got=${got:-<empty>}"; fi
}

assert_ne() {
  local label="$1" a="$2" b="$3"
  if [[ "$a" != "$b" ]]; then pass "$label"; else fail "$label" "values equal: ${a:-<empty>}"; fi
}

assert_prefix() {
  local label="$1" prefix="$2" value="$3"
  if [[ "$value" == "$prefix"* ]]; then pass "$label"; else fail "$label" "want prefix '$prefix' got '${value:-<empty>}'"; fi
}

summary() {
  echo
  echo "-- $PASSES passed, $FAILS failed --"
  if [[ $FAILS -eq 0 ]]; then echo "RESULT PASS"; return 0; else echo "RESULT FAIL"; return 1; fi
}
