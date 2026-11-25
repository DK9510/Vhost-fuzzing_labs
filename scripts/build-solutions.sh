#!/usr/bin/env bash
# Concatenate every lab's plain-text solution into solutions/ALL_SOLUTIONS.txt.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="$ROOT/solutions/ALL_SOLUTIONS.txt"
mkdir -p "$ROOT/solutions"

{
  echo "vhostlab - ALL LAB SOLUTIONS (plain text)"
  echo "generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "suite    : $ROOT"
  echo
  echo "one section per lab; each section starts at the line '==== LAB: <name> ===='"
  echo "run 'make verify LAB=<name>' to grade a lab after following its steps."
  echo
  for d in labs/*/; do
    d="${d%/}"
    lab="$(basename "$d")"
    f="$d/docs/solution.txt"
    [[ -f "$f" ]] || continue
    printf '\n\n==== LAB: %s ====\n\n' "$lab"
    cat "$f"
  done
} > "$OUT"

{
  echo "vhostlab - SOLUTION FILES"
  echo
  printf '%-26s %s\n' "LAB" "FILE"
  for d in labs/*/; do
    d="${d%/}"
    lab="$(basename "$d")"
    f="$d/docs/solution.txt"
    [[ -f "$f" ]] && printf '%-26s %s\n' "$lab" "${f#"$ROOT"/}"
  done
  echo
  printf '%-26s %s\n' "ALL" "solutions/ALL_SOLUTIONS.txt"
} > "$ROOT/solutions/INDEX.txt"

echo "wrote solutions/ALL_SOLUTIONS.txt ($(wc -l < "$OUT" | tr -d ' ') lines)"
echo "wrote solutions/INDEX.txt"
