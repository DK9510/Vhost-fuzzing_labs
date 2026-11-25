# C02 — Certificate names as a discovery source

**Case:** C2 (writeup para 16). **Ports:** 18090 / 18453. **Time:** 10 min.

## Objective

Read the TLS certificate the host hands you and turn it into a hostname list. Then separate what the
certificate *claims* from what the front end actually *serves*.

## What you get

- `https://127.0.0.1:18453` — one IP, one listener, one certificate.
- No vhost list, no DNS.

## Success criterion

`bash checks/verify.sh`. As a human:

1. `tlsx -u 127.0.0.1:18453 -san -cn -silent` (or `openssl s_client | openssl x509 -text`) prints the
   SAN set including a wildcard.
2. You can state which name in that set does **not** serve a site, and why a wildcard certificate is
   not the same thing as wildcard routing.

## Hints

1. `openssl s_client -connect 127.0.0.1:18453 -servername corp.lab </dev/null | openssl x509 -noout -text`
2. `CN` only names one host; `subjectAltName` names the rest. Modern tooling ignores `CN`.
3. Try each name as a `Host:` header before you trust it.
4. A wildcard in the certificate covers `x.corp.lab`, not `x.y.corp.lab` — and says nothing about
   which of those the server routes.
