# C04 — Content discovery on a default page

**Case:** C4 (writeup para 32-42). **Ports:** 18110 / 18473. **Time:** 20 min.

## Objective

You have a vhost that answers, but the root is an IIS default page — nothing to crawl, nothing in
Wayback. Find the application root by active discovery, and tell a real hit from a bait.

## What you get

- `chatadmin.corp.lab` on `https://127.0.0.1:18473` (send it as the `Host` header, or use
  `curl --resolve chatadmin.corp.lab:18473:127.0.0.1`).
- The IIS default page at `/`. Baseline 404 is a full IIS error page, not an empty body — size
  filtering works, but only if you measure the baseline first.

## Success criterion

`bash checks/verify.sh`. As a human: you have the app shell, you know its bundle path, and you can
explain why `/chatadmin.backup` is not the answer.

## Notes from the writeup

The author used `raft-large-directories-lowercase.txt` because IIS paths are case-insensitive, so a
lowercase wordlist halves the requests. Respect the target's rate limit; this lab is local, so
`-t 100` is safe here and would not be on a live host.
