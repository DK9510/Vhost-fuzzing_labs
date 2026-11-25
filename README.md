# vhostlab — hidden-vhost lab suite

Twelve self-contained labs, one per technique, from Dishant Kapadiya's "Finding Hidden virtual hosts"
writeup plus a keyword-routing case. One repo, one shared edge image, one lab CA, one check harness;
every lab has its own compose project, network, port pair, flag and verify script.

```
make build            # build the shared edge image
make certs            # issue per-lab leaf certs from the lab CA
make up LAB=c03-wildcard-hosts
make verify LAB=c03-wildcard-hosts
make down LAB=c03-wildcard-hosts
make up-all && make verify-all      # everything, then instances/results.json
make ports            # port map + host collisions
make list             # labs present
```

| Lab | Case | Ports | Topic |
|---|---|---|---|
| c00-full-chain | all | 18180/18543 | the writeup end to end, decoys on |
| c01-bare-ip-404 | C1 | 18080/18443 | `Server: Microsoft-HTTPAPI/2.0` 404 = vhost router |
| c02-cert-san | C2 | 18090/18453 | certificate SAN/CN → hostname list |
| c03-wildcard-hosts | C3 | 18100/18463 | wildcard label fuzzing with decoys |
| c04-content-discovery | C4 | 18110/18473 | IIS default page → raft discovery |
| c05-js-api-pivot | C5 | 18120/18483 | bundle → second vhost, 404 signatures |
| c06-browser-dns | C6 | 18130/18493 | DNS override, CA trust, DRF browsable API |
| c07-django-debug | C7 | 18140/18503 | DEBUG=True + dead SMTP → reset token → admin |
| c08-sni-routing | C8 | 18150/18513 | SNI picks the cert, Host picks the site |
| c09-decoy-fuzz | C9 | 18160/18523 | 40 hosts, 1 real, zero false positives |
| c10-keyword-vhost | C10 | 18170/18533 | `Host` contains `portal` → app; no allowlist |
| c11-silent-sni | C11 | 18190/18553 | no SNI or no Host = no answer at all (timeout) |

## Layout

```
_shared/edge      Go gateway (host/keyword/SNI routing, per-route Server header) — image vhostlab/edge:1.0
_shared/api       Django 4.2 + DRF app (DEBUG, SMTP, JWT, seed) — image vhostlab/api:1.0
_shared/certs     one CA + per-lab leaves (scripts/gen_ca.sh, issue.sh)
_shared/lib       check.sh assertions (PASS/FAIL per line, exit = fail count)
_shared/data      host-keywords.txt, vhost-labels.txt
labs/<lab>/       docker-compose.yml, edge/sites.json, sites/, checks/verify.sh, docs/
scripts/          build-edge.sh, issue-all-certs.sh, verify-all.sh, ports.sh, keyword-sweep.sh
instances/        logs + results.json (gitignored)
```

## Rules the suite follows

- A lab never requires another lab to be running; each one hands you the previous case's *output* in
  its README.
- No cross-lab state: distinct compose project, subnet, volumes, ports, certificate SANs, JWT key.
- Every lab grades itself; `make down LAB=...` cannot affect the others.
- Nothing is "done" because a container is up: `make verify-all` must be 12/12 after a cold reset.

## Addressing

Every edge publishes on **`0.0.0.0`** (explicit in each compose file: `"0.0.0.0:18080:8080"`), so the
labs are reachable from any machine on the same network — no loopback-only binding, no reverse proxy.

```
make lan                     # LAN IP, port map, firewall state, client hosts hint
make lan-hosts               # /etc/hosts block for a client machine
make lan-check               # curl every lab over the LAN IP (not loopback)
LAB_HOST=10.10.1.9 make verify-all   # grade the whole suite over the LAN path
```

- **Host header only.** Hostnames are routed by `Host:` (and, for c08/c11, by TLS SNI). They are not
  DNS names: `curl -k --resolve chatadmin.corp.lab:18463:<lab-ip>
  https://chatadmin.corp.lab:18463/` works with no resolver change.
- **Browsing from another device.** Add `instances/hosts-vhostlab.txt` (all 48 lab names → the lab
  IP) to that device's `hosts` file, or set Burp's `Override hostname resolution` — see
  `docs/burp-setup.md`. Phones have no hosts file: use a router DNS entry or Burp with the proxy
  profile.
- **TLS.** One lab CA signs every leaf: import `_shared/certs/out/ca.crt` on the client once.
- **SNI survives the LAN path.** Verified off-host through OrbStack's port forwarding: c08 still picks
  the cert by SNI and c11 still requires SNI **and** Host (wrong SNI → TLS EOF, wrong Host → zero
  bytes). Note that a plain HTTP client that connects to the IP sends SNI `<ip>`, which is exactly why
  c11 stays silent.

## Standards this suite enforces

- A matched route is not a finding; a 200 is not a finding; an exposed API root is not a finding.
  C10 grades on an authenticated dashboard, C07 on the flag from admin data, C09 on zero false
  positives.
- Case labs are technique drills; c00 is the only one where the full chain and its reportability
  question are in play.

## Docs

Every lab ships its walkthrough twice: `docs/solution.md` (formatted) and `docs/solution.txt`
(plain text, commands + expected output, readable in any terminal or editor). The `.txt` files are
concatenated into `solutions/ALL_SOLUTIONS.txt` by `scripts/build-solutions.sh`; `solutions/INDEX.txt`
maps lab → file.

## Status (2026-11-22)

Built and verified on OrbStack/macOS arm64: **12/12 labs PASS**, both after `make up-all` and after a
cold `make reset` of every lab. Isolation, LAN reachability, volume persistence and cross-lab leak
checks are recorded in `docs/ACCEPTANCE.md`.

