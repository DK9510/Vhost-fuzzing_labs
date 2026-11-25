#!/usr/bin/env bash
# Issue (or refresh) the leaf certificate for every lab that declares SANs.
# usage: issue-all-certs.sh [--force]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FORCE=""
[[ "${1:-}" == "--force" ]] && FORCE=1
bash "$ROOT/_shared/certs/gen_ca.sh"

for d in "$ROOT"/labs/*/; do
  sans_file="$d/edge/cert-sans.txt"
  [[ -f "$sans_file" ]] || continue
  sans="$(tr -d '\n' < "$sans_file")"
  cn_file="$d/edge/cert-cn.txt"
  cn="corp.lab"
  [[ -f "$cn_file" ]] && cn="$(tr -d '\n' < "$cn_file")"
  out="$d/edge/certs"
  stamp="$out/.sans"
  if [[ -z "$FORCE" && -f "$out/lab.crt" && -f "$stamp" && "$(cat "$stamp")" == "$sans" ]]; then
    echo "skip  $(basename "$d") (cert current)"
    continue
  fi
  mkdir -p "$out"
  name="$(basename "$d")"
  bash "$ROOT/_shared/certs/issue.sh" lab "$sans" "$out" "$cn" >/dev/null
  printf '%s' "$sans" > "$stamp"
  echo "issue $name  CN=$cn  SAN=$sans"
  if [[ -x "$d/edge/certs-hook.sh" ]]; then
    "$d/edge/certs-hook.sh"
  fi
done
