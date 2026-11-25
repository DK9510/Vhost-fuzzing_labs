#!/usr/bin/env bash
# vhostlab LAN access: which address the labs are published on, the /etc/hosts block a
# client machine needs, and a reachability matrix over the LAN path (not loopback).
#
#   scripts/lan.sh                 summary: LAN IP, port map, URLs, hosts hint
#   scripts/lan.sh --hosts         print the /etc/hosts block for a client machine
#   scripts/lan.sh --write-hosts   write instances/hosts-vhostlab.txt (copy to the client)
#   scripts/lan.sh --check         curl every lab's edge over the LAN IP
#
# Address override:  LAN_IP=10.10.1.10 scripts/lan.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

detect_ip() {
  local i ip
  if [[ -n "${LAN_IP:-}" ]]; then printf '%s' "$LAN_IP"; return; fi
  for i in en0 en1 en2 en3 en4 en5; do
    ip="$(ipconfig getifaddr "$i" 2>/dev/null || true)"
    if [[ -n "$ip" ]]; then printf '%s' "$ip"; return; fi
  done
  printf '127.0.0.1'
}

IP="$(detect_ip)"

# All hostnames the twelve labs route on (sites[].host, sni keys, silent allow lists),
# plus the bare keywords C10/C00 match on. Single source of truth = edge/sites.json.
hosts_list() {
  python3 - "$ROOT" <<'PY'
import json, glob, sys, os
root = sys.argv[1]
names, per_lab = set(), {}
for f in sorted(glob.glob(os.path.join(root, 'labs/*/edge/sites.json'))):
    lab = f.split(os.sep)[-3]
    d = json.load(open(f))
    n = set()
    for s in d.get('sites', []):
        if s.get('host'):
            n.add(s['host'])
    n.update((d.get('sni') or {}).keys())
    sil = d.get('silent') or {}
    n.update(sil.get('allow_sni', []) + sil.get('allow_host', []))
    for kw in d.get('keywords', []):
        if kw.get('contains'):
            n.add(kw['contains'])
    per_lab[lab] = sorted(n)
    names.update(n)
for name in sorted(names):
    if name.endswith('.'):
        continue  # trailing-dot keyword bait, not a hostname a hosts file can hold
    print(name)
PY
}

ports_of() { # <lab dir> -> host ports
  grep -oE '"[0-9.]+:[0-9]+:[0-9]+"' "$1/docker-compose.yml" \
    | tr -d '"' | awk -F: '{print $(NF-1)}' | tr '\n' ' '
}

if [[ "${1:-}" == "--hosts" || "${1:-}" == "--write-hosts" ]]; then
  block="# --- vhostlab (client machine: point every lab name at the lab host) ---"
  block+="$(printf '\n%s' "$IP")"
  for n in $(hosts_list); do block+=" $n"; done
  block+="$(printf '\n# --- end vhostlab ---')"
  if [[ "${1:-}" == "--write-hosts" ]]; then
    mkdir -p instances
    printf '%s\n' "$block" > instances/hosts-vhostlab.txt
    echo "wrote instances/hosts-vhostlab.txt"
    echo
  fi
  printf '%s\n' "$block"
  cat <<EOF

install on the client (needs root/admin on that machine, not on this one):
  macOS / Linux   sudo tee -a /etc/hosts < hosts-vhostlab.txt
  Windows         notepad C:\\Windows\\System32\\drivers\\etc\\hosts  (append the block)
  phone           no hosts file - use a local DNS entry on the router, or Burp
                  "Override hostname resolution" -> * -> $IP
verify:           dscacheutil -q host -a name chatadmin.corp.lab   (macOS)
EOF
  exit 0
fi

if [[ "${1:-}" == "--check" ]]; then
  printf 'LAB                        HTTP   HTTPS\n'
  fails=0
  for d in labs/*/; do
    lab="$(basename "$d")"
    [[ -f "$d/docker-compose.yml" ]] || continue
    read -r hp sp <<<"$(ports_of "$d")"
    # c11 answers nothing without SNI+Host: a 000/timeout there is correct behaviour
    hc="$(curl -s -o /dev/null -w '%{http_code}' --max-time 6 "http://$IP:$hp/" 2>/dev/null)"
    sc="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 6 "https://$IP:$sp/" 2>/dev/null)"
    if [[ "$hc" == "000" && "$lab" != c11-* ]]; then fails=$((fails+1)); fi
    printf '%-26s %-6s %s\n' "$lab" "${hc:-000}" "${sc:-000}"
  done
  echo
  [[ $fails -eq 0 ]] || { echo "$fails lab(s) unreachable over $IP"; exit 1; }
  echo "all labs answer over http://$IP:<port> (c11 times out by design without SNI+Host)"
  exit 0
fi

cat <<EOF
vhostlab on the LAN
  bind address  0.0.0.0 (every edge publishes HTTP+HTTPS on all interfaces)
  LAN address   $IP        (override: LAN_IP=<addr> scripts/lan.sh)
  firewall      $(/usr/libexec/ApplicationFirewall/socketfirewall --getglobalstate 2>/dev/null || /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | head -1)

EOF
printf '%-26s %s\n' "LAB" "PORTS (host)"
for d in labs/*/; do
  lab="$(basename "$d")"
  [[ -f "$d/docker-compose.yml" ]] || continue
  printf '%-26s %s\n' "$lab" "$(ports_of "$d")"
done
cat <<EOF

reach it by name from a client machine
  scripts/lan.sh --write-hosts            # instances/hosts-vhostlab.txt -> client /etc/hosts
  scripts/lan.sh --hosts                  # print the same block

reach it without touching DNS (curl keeps the Host header, resolver untouched)
  curl -k --resolve chatadmin.corp.lab:18463:$IP https://chatadmin.corp.lab:18463/

grade the labs over the LAN path instead of loopback
  LAB_HOST=$IP make verify-all

browse with TLS
  import _shared/certs/out/ca.crt on the client (phone: profile + "trust for full access")
EOF
