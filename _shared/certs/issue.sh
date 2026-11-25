#!/usr/bin/env bash
# Issue a leaf cert signed by the lab CA.
# usage: issue.sh <name> <san-csv> <outdir> [cn]
#   issue.sh corp.lab "DNS:corp.lab,DNS:*.corp.lab" labs/c01-bare-ip-404/edge/certs
set -euo pipefail
NAME="${1:?name}"
SANS="${2:?san csv}"
OUTDIR="${3:?outdir}"
CN="${4:-$NAME}"
HERE="$(cd "$(dirname "$0")" && pwd)"
CA_OUT="${CA_OUT:-$HERE/out}"
if [[ ! -f "$CA_OUT/ca.crt" ]]; then
  "$HERE/gen_ca.sh" >/dev/null
fi
mkdir -p "$OUTDIR"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
openssl genrsa -out "$tmp/$NAME.key" 2048 2>/dev/null
openssl req -new -key "$tmp/$NAME.key" -subj "/C=IN/O=vhostlab/CN=${CN:0:64}" -out "$tmp/$NAME.csr"
{
  echo "basicConstraints=CA:FALSE"
  echo "keyUsage=digitalSignature,keyEncipherment"
  echo "extendedKeyUsage=serverAuth"
  echo "subjectAltName=$SANS"
} > "$tmp/ext.cnf"
openssl x509 -req -in "$tmp/$NAME.csr" -CA "$CA_OUT/ca.crt" -CAkey "$CA_OUT/ca.key" \
  -CAcreateserial -days 825 -sha256 -extfile "$tmp/ext.cnf" -out "$tmp/$NAME.crt" 2>/dev/null
cp "$tmp/$NAME.key" "$tmp/$NAME.crt" "$OUTDIR/"
echo "issued $OUTDIR/$NAME.crt  SAN=$SANS"
