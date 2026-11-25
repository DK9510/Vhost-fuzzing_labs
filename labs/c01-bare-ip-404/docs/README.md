# C01 — Bare-IP 404 fingerprint

**Case:** C1 (writeup para 11-14). **Ports:** 18080 / 18443. **Time:** 10 min.

## Objective

A host in scope answers on 443 but gives you nothing useful. Establish **why**: the status,
the `Server:` header and the body size tell you a virtual-host router is in front and your request
has no hostname it recognises. Then prove the contrast by sending a hostname it does know.

## What you get

- `https://127.0.0.1:18443/` and `http://127.0.0.1:18080/` — the "IP".
- No vhost list. One hostname in this lab is valid; you are expected to notice the difference in
  behaviour when you send it.

## Success criterion

`bash checks/verify.sh` — every assertion passes. As a human, you are done when you can state, from
your own requests only:

1. exact status code of the bare-IP request,
2. the `Server:` value (and why it implies virtual-host routing),
3. the body length, and
4. the two response headers that change when a valid hostname is presented.

## Files

- `docs/hints.md` — progressive hints.
- `docs/solution.md` — the reference answer, including the writeup paragraph it maps to.
