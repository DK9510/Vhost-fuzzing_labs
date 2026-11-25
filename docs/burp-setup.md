# Burp setup for the vhost labs

No lab needs `/etc/hosts`. Two settings make raw `Host:` headers unnecessary and browsers behave.

## 1. DNS override (per project)

The labs are published on `0.0.0.0`, so use **the lab host's LAN IP** when Burp runs on another
machine, and `127.0.0.1` only when Burp runs on the lab host itself (`make lan` prints the IP and
`instances/hosts-vhostlab.txt` has the full name list).

Burp → **Settings → Network → DNS** → *Override hostname resolution*:

```
*.corp.lab      -> <lab-ip>
*.internal.corp.lab -> <lab-ip>
portal          -> <lab-ip>
```

Ports still matter: browse `https://chatadmin.corp.lab:18463/` (or map per lab).

## 2. TLS trust

Import the lab CA once:

```
_shared/certs/out/ca.crt
```

- Burp: **Settings → Network → TLS → Trusted CA certificates → Import**.
- macOS keychain (browser trust): `scripts/import-ca.sh` (run by hand; needs sudo).
- Firefox has its own store: import the same file under Certificates → Authorities.

Every lab leaf is signed by that CA, so one import covers all twelve. Without it you get
`NET::ERR_CERT_AUTHORITY_INVALID` and Burp shows the handshake as failed.

## 3. Host-header fuzzing in Intruder

For C03/C09/C10, send the request to Intruder and make the **Host** header the payload position:

```
GET /app HTTP/1.1
Host: §portal§.corp.lab
```

- Payloads: `_shared/data/vhost-labels.txt` (C03/C09) or `_shared/data/host-keywords.txt` (C10).
- Options → Grep - Match: `X-App:`, `Disallow: /app`, `Chat Admin`.
- Columns: status, length, and the `Server:` header (`Options → Grep - Extract`).

For C10 also add a second payload list of *bare* words (`portal`, `app.portal.test`,
`portalstg.app.test`) — a `Host: FUZZ.corp.lab` run alone will never find a keyword rule.

## 4. Things that look like findings and are not

- `Server:` values are emulated, not a real IIS build: do not report version-based CVEs from a lab.
- An open `/api/` root (C05/C06) is a route listing, not data.
- A certificate mismatch (C08) is an observation until you show impact.
- A 403 from a matched vhost (C03/C09/C10 bait) means a rule exists, nothing more.
- A request that times out (C11) is silence, not a 404: raise Burp's timeout and do not read
  "no response" as "no route".
