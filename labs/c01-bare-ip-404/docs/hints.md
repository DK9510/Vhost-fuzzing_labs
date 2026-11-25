# Hints — C01

1. Always read the response *headers*, not just the status. `curl -skI https://127.0.0.1:18443/`.
2. A `Server:` value that names the HTTP platform rather than an application (`Microsoft-HTTPAPI/2.0`)
   is a strong signal that the application sits behind host-based routing.
3. Compare the body length against a failed request to a path (`/admin`): identical means the wall,
   not the path, produced the response.
4. Some hostnames are valid. The lab publishes none, but the gateway serves one for the domain
   `corp.lab`. Try the obvious candidates, and try the same request over plain HTTP.
5. When a hostname is right, both the status and the `Server:` header change at once — that is the
   contrast you are looking for.
