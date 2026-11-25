# Acceptance record

Gates from the build plan, run on 2026-11-22 (OrbStack, macOS arm64, Docker 29.4).

| Gate | Method | Result |
|---|---|---|
| All labs green after a cold start | `make up-all && make verify-all` | **12/12 PASS** (235 assertions) |
| All labs green after a cold reset | `make reset LAB=<each>` (down -v, up, re-seed) then `make verify-all` | **12/12 PASS** |
| One lab down does not disturb the others | `make down LAB=c01` → verify c01/c03/c07/c10 | c01 FAIL (expected: nothing listening), c03/c07/c10 PASS; c01 PASS again after `make up` |
| LAN reachability, not just loopback | `curl --resolve <host>:<port>:10.10.1.9` | c03 200, c07 200, c10 200, c00 200, c11 200 |
| Whole suite graded over the LAN path | `LAB_HOST=10.10.1.9 make verify-all` | **12/12 PASS** (same assertions, no 127.0.0.1) |
| Off-host reachability + SNI/Host preserved | `docker run --network host ...` from the OrbStack VM netns → `10.10.1.9` | c01 bare 404 `Microsoft-HTTPAPI/2.0`, c01 `ok.corp.lab` 200, c03/c07 200, c10 keyword 200; c11: SNI+Host ok → `HTTP/1.1 200`, bad Host → 0 bytes, bad SNI → TLS EOF |
| Volume persistence across container restart | `docker restart vhc07-api` → `verify.sh` | PASS, 22 assertions (users/chats/flag survived) |
| No flags baked into site content | `grep -rl 'FLAG{' labs/*/sites` | no matches |
| No cross-lab hostname leakage | grep for c08 hostnames outside c08 | none |
| Port map has no host collisions | `make ports` | 22/22 ports bound by their own lab |

Assertion counts per lab (from `instances/results.json`):

```
c00 20   c01 13   c02 11   c03 18   c04 15   c05 16
c06 11   c07 22   c08 11   c09 15   c10 26   c11 20      total 198 (+37 in optional tool-parity paths)
```

Known non-fatal notes:

- `ffuf` needs low concurrency against the lab gateway (`-t 40`); at `-t 100` a request can be dropped
  and a hit missed. The gateway sets `MaxIdleConnsPerHost: 128`, which removed the flakiness observed
  at default transport settings.
- macOS `openssl` is LibreSSL: `x509 -ext subjectAltName` is unsupported, use `-text | sed -n
  '/Subject Alternative Name/,+1p'`.
- `tlsx` plain output drops a wildcard SAN from its short form; use `-json` and read `subject_an`.
- Containerised `docker build` fails when the registry is unreachable through the VPN; `make build`
  falls back to the host Go toolchain + a `scratch` base.
