# Solution — C01 (bare-IP 404)

Maps to writeup para 11-14: 50-60 IPs in scope, 3-4 with 443 open, the page says
`404 Not found` with `Server: Microsoft-HTTPAPI/2.0`, and that fingerprint means "there is a vhost".

## Requests

```bash
# 1. the wall
curl -skD - -o /dev/null https://127.0.0.1:18443/ | tr -d '\r'
#    HTTP/2 404
#    content-type: text/html
#    server: Microsoft-HTTPAPI/2.0
#    content-length: 0
#    (HEAD omits content-length; --http1.1 shows the classic status line)

# 2. the wall is a wall, not a missing file
curl -sk -o /dev/null -w '%{http_code} %{size_download}\n' https://127.0.0.1:18443/admin
#    404 0

# 3. the contrast
curl -skI -H 'Host: ok.corp.lab' https://127.0.0.1:18443/
#    HTTP/1.1 200 OK
#    Server: Microsoft-IIS/10.0
```

## Why this matters

- `Server: Microsoft-HTTPAPI/2.0` is the http.sys layer answering before any site binds the request:
  no hostname it recognises, so no application.
- The two distinct `Server` values are the tell. `Microsoft-HTTPAPI/2.0` = "no site matched".
  `Microsoft-IIS/10.0` = "a site matched and answered".
- This is the observation that converts "one boring IP" into a target: the site exists, you are
  addressing it wrong.

## Next case

C02 takes the same IP and reads the TLS certificate, which usually names the site you are missing.
