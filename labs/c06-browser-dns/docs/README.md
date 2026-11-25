# C06 — Browser path (DNS override, CA trust, DRF browsable API)

**Case:** C6 (writeup para 54). **Ports:** 18130 / 18493. **Time:** 15 min.

## Objective

Stop using raw `Host:` headers. Make the hostnames resolve and the certificate trusted so the SPA and
the API behave like they do for a real user — that is where DRF's browsable API, missing headers and
sequence bugs show up.

## What you get

- `chatadmin.corp.lab` (SPA) and `chat-api.corp.lab` (DRF, `BROWSABLE=1`, `DEBUG=0`).
- Lab CA at `_shared/certs/out/ca.crt`, leaf at `labs/c06-browser-dns/edge/certs/lab.crt`.

## Setup (one time)

- Burp: Settings → Network → DNS → *Override hostname resolution*: `*.corp.lab` → `127.0.0.1` (or the
  lab host's LAN IP when Burp runs on another machine — `make lan` prints it). Import
  `_shared/certs/out/ca.crt` into Burp's TLS trust and into the browser/keychain.
- Or `/etc/hosts` (needs sudo): run `scripts/hosts.sh` by hand — it emits a LAN-IP block that also
  works on a phone/laptop; append the loopback variant only for the lab host itself.
- Browse `https://127.0.0.1:18493/` with `Host` override, or `https://chat-api.corp.lab:18493/`.

## Success criterion

`bash checks/verify.sh` (asserts content negotiation, cert chain, no redirect loops). As a human: you
see the DRF browsable page in a browser with no certificate warning, and the SPA loads its bundle.

## Hints

1. `Accept: text/html` is what makes DRF render the browsable API; tools default to JSON.
2. If the browser warns, the CA is not trusted — fix that before blaming the lab.
3. Check for redirect loops (`# Redirects:` in curl) — a classic browser-only failure on vhosts.
