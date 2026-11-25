# C03 — Wildcard Host-header fuzzing with decoys

**Case:** C3 (writeup para 16, 30). **Ports:** 18100 / 18463. **Time:** 25 min.

## Objective

The certificate says `*.corp.lab`, the IP answers 404 to everything. Enumerate labels, send them as
`Host:` headers, and find the one vhost that actually serves an application — without claiming the
decoys.

## What you get

- `https://127.0.0.1:18463` — one IP, 12 vhosts, no tell in the root pages.
- `_shared/data/vhost-labels.txt` — the label list a normal recon pass would produce.

## Traps

- Ten decoys return a **byte-identical** welcome page: status and length triage will not separate them.
- One vhost answers **403**: an anomaly, not the answer.

## Success criterion

`bash checks/verify.sh`. As a human: you found the one host that has both `/robots.txt` and
`/chatadmin`, and you can say why the 403 host is not it.

## Hints

1. Baseline one decoy root, hash it, and treat "different body" as the signal, not "different length".
2. Request something a real application would have (`/robots.txt`, a well-known app path) on every
   candidate; the decoys 404 there.
3. `ffuf -u https://127.0.0.1:18463/chatadmin -H 'Host: FUZZ.corp.lab' -w <labels> -fc 403,404`
4. Read `robots.txt` on the winner — it points at the app you need in the next case.
