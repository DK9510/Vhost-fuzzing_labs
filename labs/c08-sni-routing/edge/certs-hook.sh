#!/usr/bin/env bash
# Second leaf for the internal zone; only presented when the client asks for it by SNI.
set -euo pipefail
LAB="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$LAB/../.." && pwd)"
out="$LAB/edge/certs"
if [[ -f "$out/internal.crt" && -f "$out/internal.key" ]]; then
  exit 0
fi
bash "$ROOT/_shared/certs/issue.sh" internal \
  "DNS:internal.corp.lab,DNS:*.internal.corp.lab" "$out" "internal.corp.lab" >/dev/null
echo "issued internal.crt (SCOPE: only reachable via SNI internal.corp.lab)"
