# C05 — JS bundle → second vhost (404 signatures)

**Case:** C5 (writeup para 44-48). **Ports:** 18120 / 18483. **Time:** 20 min.

## Objective

The SPA you found calls a backend on a different hostname. Prove the hostname is real by comparing
**404 signatures**, not by trusting a string in a bundle — and recognise the decoy URL.

## What you get

- `chatadmin.corp.lab` → SPA at `/chatadmin`, bundle at `/chatadmin/assets/app.js`.
- `chat-api.corp.lab` → not linked, not in DNS.
- One hostname in the bundle that does not exist.

## Success criterion

`bash checks/verify.sh`. As a human: you extracted `API_BASE`, hit `/api/`, saw a JSON surface, and
can explain why the `STAGING_API` hostname is a dead end.

## Hints

1. `curl -sk -H 'Host: chatadmin.corp.lab' https://127.0.0.1:18483/chatadmin/assets/app.js`
2. Compare the `Server:` header of a 404 on the candidate vhost against a 404 from the bare IP
   (`Microsoft-IIS/10.0` vs `Microsoft-HTTPAPI/2.0`). Same status, different owner.
3. `/api/` is the documented root; `/api/chat-status` proves the base is live.
4. The decoy hostname answers 404 with the *HTTPAPI* body — i.e. it was never a vhost.
