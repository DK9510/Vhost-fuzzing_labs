#!/usr/bin/env bash
# Print the /etc/hosts block for the labs. Since the labs publish on 0.0.0.0, the block points at the
# lab host's LAN address (LAN_IP=<addr> to override) instead of loopback, so it works on a client
# machine. Run the append by hand: the agent terminal rewrites sudo, so this script never edits the
# file itself. To write the block to a file you can copy: bash scripts/lan.sh --write-hosts
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec bash "$ROOT/scripts/lan.sh" --hosts
