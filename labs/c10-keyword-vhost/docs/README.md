# C10 — Keyword-matched vhost: a word in the Host header

**Case:** C10 (your case; real-world front-end pattern). **Ports:** 18170 / 18533. **Time:** 30 min.

## Objective

One application is not addressed by a hostname at all: the front end routes on a **substring of the
Host header**. `portal`, `portalstg.app.test`, `app.portal.test`, `PORTAL`, `portal:443` and even
`portal.attacker.test` all land on it. DNS enumeration will never show it; only whole-value Host
fuzzing will.

## What you get

- `https://127.0.0.1:18533` — one IP.
- `chatadmin.corp.lab` (an exact vhost, for the precedence test).
- `scripts/keyword-sweep.sh` and `_shared/data/host-keywords.txt` (the sweep technique).

## Traps

- `vpn.corp.lab` → 403: a keyword rule that matched and refuses. Anomaly, not the app.
- `portal.` (trailing dot) → 404: the suffix rule fires first, so a dot-qualified name misses the app.
- The dashboard needs a real login: a 200 on `/` is discovery, not a finding.

## Success criterion

`bash checks/verify.sh`. As a human: `/dashboard` returns data with a token, and you can state that
the routing has **no domain allowlist** — any attacker-controlled hostname reaches the app.

## Hints

1. Fuzz the **whole** Host value: `ffuf -u https://127.0.0.1:18533/ -H 'Host: FUZZ' -w <words> -fs <wall> -ac`
2. Sweep the shapes: bare word, `word.<base>`, `word-x.<base>`, `x-word.<base>`, `WORD`, `word:443`.
3. A hit needs at least two shapes agreeing — one weird status is noise.
4. Read the `X-App` header of a candidate; the app identifies itself.
5. Then log in (`alex@corp.lab` / `agent-pass-2026`) and open `/dashboard`.
