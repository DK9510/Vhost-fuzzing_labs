#!/usr/bin/env bash
# Print the lab port map and flag ports already bound on the host.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
printf '%-26s %-14s %s\n' "LAB" "PORTS" "BOUND?"
for d in labs/*/; do
  lab="$(basename "$d")"
  [[ -f "$d/docker-compose.yml" ]] || continue
  ports="$(grep -oE '"[0-9.]+:[0-9]+:[0-9]+"|"[0-9]+:[0-9]+"' "$d/docker-compose.yml" \
    | tr -d '"' | awk -F: '{print $(NF-1)}' | tr '\n' ' ')"
  status=""
  for p in $ports; do
    if lsof -nP -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1; then
      status="$status $p=BOUND"
    fi
  done
  printf '%-26s %-14s %s\n' "$lab" "$ports" "${status:-free}"
done
