#!/usr/bin/env bash
# Run every lab's verify script and aggregate. Writes instances/results.json.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p instances instances/logs
results="$ROOT/instances/results.json"
: > "$results.tmp"
total=0; ok=0
printf '%-26s %s\n' "LAB" "RESULT"
for d in labs/*/; do
  lab="$(basename "$d")"
  [[ -f "$d/checks/verify.sh" ]] || continue
  total=$((total + 1))
  log="$ROOT/instances/logs/${lab}.log"
  if bash "$d/checks/verify.sh" > "$log" 2>&1; then
    ok=$((ok + 1)); verdict=PASS
  else
    verdict=FAIL
  fi
  printf '%-26s %s\n' "$lab" "$verdict"
  passes="$(grep -c '^PASS' "$log" || true)"
  fails="$(grep -c '^FAIL' "$log" || true)"
  printf '{"lab":"%s","case":"%s","verdict":"%s","passes":%s,"fails":%s,"log":"%s"}\n' \
    "$lab" "${lab%%-*}" "$verdict" "${passes:-0}" "${fails:-0}" "instances/logs/${lab}.log" >> "$results.tmp"
done
{
  echo "{"
  echo "  \"generated\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
  echo "  \"labs_total\": $total,"
  echo "  \"labs_passed\": $ok,"
  echo "  \"results\": ["
  awk 'NR>1{print "    " prev ","} {prev=$0} END{print "    " prev}' "$results.tmp" | sed '/^    $/d'
  echo "  ]"
  echo "}"
} > "$results"
rm -f "$results.tmp"

echo
echo "== $ok/$total labs passed =="
[[ $ok -eq $total && $total -gt 0 ]]
