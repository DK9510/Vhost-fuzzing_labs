# Solution — C08 (SNI vs Host)

```bash
U=127.0.0.1:18513
fp() { openssl s_client -connect $U ${1:+-servername $1} </dev/null 2>/dev/null \
       | openssl x509 -noout -fingerprint -sha256; }
fp corp.lab              # public cert
fp internal.corp.lab     # internal cert  (different fingerprint)
fp nothing.corp.lab      # default cert

# routing ignores SNI entirely
curl -sk -H 'Host: admin.internal.corp.lab' https://$U/ | grep -o 'Internal Admin'
# 200 + body, while the certificate presented was the public one
```

What the case teaches, and what it protects you from:

- A **mismatch warning** is a certificate observation. It is not access to the internal zone. In this
  lab the internal site answers on the public certificate because routing is by Host.
- Conversely, holding the internal certificate does not unlock `app.corp.lab`.
- So "certificate has a different name" is a lead about *naming*, and "Host header reaches a site" is
  a lead about *routing*. Two separate findings, each needing its own impact.
- Unknown SNI returning the default cert is why passive certificate grabs (tlsx, crt.sh) surface names
  you have never asked about.
