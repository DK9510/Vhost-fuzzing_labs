#!/usr/bin/env bash
# keyword-sweep.sh — reusable Host-header keyword sweep.
#
#   ./keyword-sweep.sh https://127.0.0.1:18533 words.txt [base-domain]
#
# For every word it sends 7 Host shapes and logs one JSONL row each:
#   W | W.<base> | W-x.<base> | x-W.<base> | W.attacker.test | UPPER(W) | W:443
# A row is flagged "hit": true only when the fingerprint (status+len+sha1+Server)
# differs from the baseline AND at least one other shape for the same word agrees.
#
# Baseline = the response to a hostname that cannot exist (zz-no-such-host.invalid).
set -uo pipefail

URL="${1:?usage: keyword-sweep.sh <url> <wordlist> [base-domain]}"
WORDS="${2:?wordlist required}"
BASE="${3:-corp.lab}"
OUT="${OUT:-/tmp/keyword-sweep.jsonl}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fp() { # fp <label> <host>
  local label="$1" host="$2"
  local hdr body code len sha srv app
  hdr="$(curl -sk -D "$TMP/h" -o "$TMP/b" --max-time 10 -H "Host: $host" "$URL" -w '%{http_code}')"
  code="$hdr"
  len="$(wc -c < "$TMP/b" | tr -d ' ')"
  sha="$(shasum -a 1 "$TMP/b" | awk '{print $1}')"
  srv="$(tr -d '\r' < "$TMP/h" | awk -F': ' 'tolower($1)=="server"{print $2; exit}')"
  app="$(tr -d '\r' < "$TMP/h" | awk -F': ' 'tolower($1)=="x-app"{print $2; exit}')"
  printf '{"shape":"%s","host":"%s","status":%s,"len":%s,"sha1":"%s","server":"%s","x_app":"%s"}\n' \
    "$label" "$host" "$code" "$len" "$sha" "$srv" "$app"
}

BASE_FP="$(fp baseline "zz-no-such-host.invalid" | jq -c '{status,len,sha1,server}')"
: > "$OUT"

while read -r w; do
  [[ -z "$w" || "$w" == \#* ]] && continue
  rows="$TMP/$w.jsonl"
  : > "$rows"
  fp "bare"            "$w"                       >> "$rows"
  fp "word.base"       "$w.$BASE"                 >> "$rows"
  fp "word-x.base"     "$w-x.$BASE"               >> "$rows"
  fp "x-word.base"     "x-$w.$BASE"               >> "$rows"
  fp "word.attacker"   "$w.attacker.test"         >> "$rows"
  fp "WORD"            "$(printf '%s' "$w" | tr '[:lower:]' '[:upper:]')" >> "$rows"
  fp "word:443"        "$w:443"                   >> "$rows"

  # how many distinct shapes produced a fingerprint other than the baseline?
  # (two shapes agreeing is the minimum that separates a real rule from one-off noise)
  off="$(jq -c 'select(({status,len,sha1,server}) != $b)' --argjson b "$BASE_FP" "$rows" | wc -l | tr -d ' ')"
  jq -c --arg w "$w" --argjson b "$BASE_FP" --argjson o "${off:-0}" \
     '. + {word:$w, baseline:($b), shapes_off:($o|tonumber), hit:(($o|tonumber) >= 2)}' "$rows" >> "$OUT"
done < "$WORDS"

hits="$(jq -r 'select(.hit and .shape=="bare") | .word' "$OUT" 2>/dev/null | sort -u | tr '\n' ' ')"
echo "wrote $OUT ($(wc -l < "$OUT" | tr -d ' ') rows)"
echo "words with a repeated off-baseline fingerprint: ${hits:-<none>}"
