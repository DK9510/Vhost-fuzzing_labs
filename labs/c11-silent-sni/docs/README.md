# C11 — Silent front end: no SNI or no Host, no answer

**Case:** C11 (your case: routing that drops instead of answering). **Ports:** 18190 / 18553. **Time:** 20 min.

## Objective

A front end that answers nothing unless the TLS handshake carries the right SNI **and** the request
carries the right Host. Bare IP, wrong SNI, wrong Host: the socket stays open and no byte comes back.
Learn to tell silence from 404/403/reset — silence is the hardest evidence to work with.

## What you get

- `https://127.0.0.1:18553` and `http://127.0.0.1:18190` — nothing answers there.
- The site is `ops.corp.lab` (Ops Console). The name has to come from somewhere else: this front end
  will not hand you a certificate or an error page.

## Rules of the lab

- `require_sni` — no SNI or an unexpected SNI stalls the handshake; no ServerHello is sent.
- `require_host` — the Host is compared literally (case and port normalised, trailing dot **not**
  normalised). A mismatch is dropped after the handshake with no status line.
- The edge holds the connection ~10-20 s and never writes a byte, so what you observe is your client's
  own timeout.

## Success criterion

`bash checks/verify.sh` (20 assertions). As a human: you can say which of your tools would have reported
"nothing here", and why that is not evidence of absence.

## Hints

1. `curl` exit code **28** = timeout. Status `000` alone proves nothing — a TCP reset looks similar.
2. No SNI means no certificate: `openssl s_client` without `-servername` gets nothing back. This is why
   passive certificate discovery fails against such a front end.
3. On `:80` there is no SNI — only Host. Confirm the name there before blaming TLS.
4. The allow-list is literal: `ops.corp.lab:443` matches, `ops.corp.lab.` does not.
5. Burp: raise the request timeout and expect "Connection closed / timed out" entries; ffuf needs
   `-timeout 3` and low concurrency or one silent host stalls the run.
