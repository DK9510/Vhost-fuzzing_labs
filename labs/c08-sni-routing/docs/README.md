# C08 — SNI vs Host (two certificates, one listener)

**Case:** C8 (writeup para 16, SNI detail). **Ports:** 18150 / 18513. **Time:** 15 min.

## Objective

Separate the two controls that get conflated in vhost work: **SNI** picks the certificate, the
**Host header** picks the site. Learn what a mismatch actually means so you never report the wrong one.

## What you get

- `app.corp.lab` (public) and `admin.internal.corp.lab` (internal zone).
- `lab.crt` (`*.corp.lab`) and `internal.crt` (`*.internal.corp.lab`), served by SNI.

## Success criterion

`bash checks/verify.sh` — the 4-way matrix: SNI match/mismatch × Host match/mismatch.

## Hints

1. `openssl s_client -connect 127.0.0.1:18513 -servername internal.corp.lab </dev/null | openssl x509 -noout -text`
2. Fingerprint both certs and compare: different SNI, different certificate.
3. Send `Host: admin.internal.corp.lab` while presenting the public certificate — what happens? (200,
   with a certificate warning.)
4. Unknown SNI falls back to the default certificate. That is the passive-grab path tlsx uses.
