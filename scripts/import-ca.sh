#!/usr/bin/env bash
# Import the lab CA into the login keychain so browsers trust the lab certificates.
# Run by hand: the agent terminal rewrites sudo, so this is not executed automatically.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CA="$ROOT/_shared/certs/out/ca.crt"
[[ -f "$CA" ]] || { echo "CA missing: run make certs"; exit 1; }
echo "about to trust: $CA"
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$CA"
echo "imported. Revert with:"
echo "  sudo security delete-certificate -c 'vhostlab Lab CA' /Library/Keychains/System.keychain"
