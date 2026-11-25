# Solution — C06 (browser path)

Maps to writeup para 54: "set Burp's Networking DNS resolution to resolve those applications directly
from the browser so we don't need to rename the Host header on every request".

```bash
# content negotiation, the bit that makes DRF browsable
curl -sk -H 'Host: chat-api.corp.lab' -D - -o /dev/null https://127.0.0.1:18493/api/ | grep -i content-type
# application/json
curl -sk -H 'Host: chat-api.corp.lab' -H 'Accept: text/html' -D - -o /dev/null \
  https://127.0.0.1:18493/api/ | grep -i content-type
# text/html; charset=utf-8
curl -sk -H 'Host: chat-api.corp.lab' -H 'Accept: text/html' https://127.0.0.1:18493/api/ | grep -o 'Django REST framework' | head -1

# cert trust
openssl verify -CAfile _shared/certs/out/ca.crt labs/c06-browser-dns/edge/certs/lab.crt
```

Burp recipe (Settings → Network → DNS, then TLS):

```
Override hostname resolution:  *.corp.lab  ->  127.0.0.1
TLS:  import _shared/certs/out/ca.crt  (Proxy → options → TLS → trust)
```

What the case is really for: once the browser resolves the vhosts, the API's browsable pages expose
endpoint shapes (`/api/auth/password_reset`, `/api/chats`) that become the input to C07. Also, the
absence of CORS errors here is deliberate: no `Access-Control-Allow-Origin` is configured, and a
report based only on "CORS missing" is not this lab's target.

Next case: C07 is the exploit — the API you just browsed has `DEBUG=True` and broken mail.
