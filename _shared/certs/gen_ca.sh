#!/usr/bin/env bash
# Create the shared lab CA once (idempotent).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${CA_OUT:-$HERE/out}"
mkdir -p "$OUT"
if [[ -f "$OUT/ca.key" && -f "$OUT/ca.crt" ]]; then
  echo "CA already present: $OUT/ca.crt"
  exit 0
fi
openssl genrsa -out "$OUT/ca.key" 4096 2>/dev/null
openssl req -x509 -new -nodes -key "$OUT/ca.key" -sha256 -days 3650 \
  -subj "/C=IN/O=vhostlab/OU=lab/CN=vhostlab Lab CA" -out "$OUT/ca.crt"
chmod 600 "$OUT/ca.key"
echo "created $OUT/ca.crt"
openssl x509 -in "$OUT/ca.crt" -noout -subject -dates
