# Solution — C02 (certificate SAN/CN)

Maps to writeup para 16: "use Tlsx to extract and parse the certificates for the TLS handshake and
grab the SAN and CN, which is either a hostname like test.prod.api.example.com or a wildcard
`*.example.com`".

```bash
tlsx -u 127.0.0.1:18453 -san -cn -silent
# 127.0.0.1:18453 [corp.lab]
# 127.0.0.1:18453 [mail.corp.lab]

tlsx -u 127.0.0.1:18453 -san -cn -silent -json | jq '{cn:.subject_cn, an:.subject_an, wc:.wildcard_certificate}'
# {"cn":"corp.lab","an":["corp.lab","*.corp.lab","mail.corp.lab"],"wc":true}
```

What the lab grades:

- `*.corp.lab` is present → any single-label subdomain is a legitimate certificate name, so the next
  step is enumerating labels, not guessing domains.
- `mail.corp.lab` is in the certificate but returns the HTTPAPI 404 → a name in a certificate is a
  candidate, never a finding.
- `zzz.corp.lab` also 404s → wildcard *certificate* ≠ wildcard *routing*.

Next case: C03 fuzzes those labels as `Host:` headers against the same IP.
