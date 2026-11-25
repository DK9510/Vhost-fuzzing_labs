# C00 — Full chain (the writeup, end to end)

**Case:** all. **Ports:** 18180 / 18543. **Time:** 60-90 min.

## Objective

One IP, everything on: bare-IP wall, wildcard certificate, decoy vhosts, content discovery, JS pivot,
second vhost, Django `DEBUG=True` with broken SMTP, and the keyword-routed portal. Walk it as the
author did and finish with admin access.

## What you get

- `https://127.0.0.1:18543` and `http://127.0.0.1:18180`.
- Nothing else. No hostname list, no walkthrough in the target, no hints in the images.

## Success criterion

`bash checks/verify.sh` (the reference walk, every stage asserted). As a human: you have the flag from
`/api/chats` as admin, reached through the reset token you found in the 500.

## Order that works

1. bare IP → 404 + `Microsoft-HTTPAPI/2.0`
2. certificate → `*.corp.lab`
3. label sweep → the vhost with `robots.txt`
4. content discovery → `/chatadmin`
5. bundle → `chat-api.corp.lab`, confirmed by its 404 signature
6. reset → 500 → token → confirm → login → chats
7. keyword sweep → `portal` app on the same IP (`X-App: portal`)
8. decoys and the 403 bait: explain why neither is a finding

## Hints

Only one: every stage is one of the case labs (C01-C10), in order. If you are stuck, open the matching
case lab — the technique is identical, the content differs.
