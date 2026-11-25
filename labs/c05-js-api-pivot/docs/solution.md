# Solution — C05 (JS pivot)

Maps to writeup para 44-48: "the backend APIs for this application is on another domain/hostname...
since it's a vhost, that API hostname should be hosted on the same IP. I checked via repeater the same
way I found the chatdashboard hostname — and this 404 is different, it says Server: Microsoft-IIS/10.0."

```bash
S='Host: chatadmin.corp.lab'; A='Host: chat-api.corp.lab'; U=https://127.0.0.1:18483

curl -sk -H "$S" $U/chatadmin/assets/app.js | grep -E 'API_BASE|STAGING_API'
# API_BASE: "https://chat-api.corp.lab/api"
# STAGING_API: "https://chat-staging.corp.lab/api"

curl -skI -H "$A" $U/nope | grep -i server      # Server: Microsoft-IIS/10.0
curl -skI         $U/nope | grep -i server      # Server: Microsoft-HTTPAPI/2.0

curl -sk -H "$A" $U/api/ | jq .
curl -sk -H "$A" $U/api/chat-status | jq .
curl -sk -H 'Host: chat-staging.corp.lab' $U/api/ -o /dev/null -w '%{http_code}\n'   # 404
```

The rule this case teaches: a URL inside a bundle is a hypothesis. Two independent signals confirm a
vhost — a `Server:` header that belongs to a site, and a path that answers with that site's
application (`/api/`). The decoy has neither, which is exactly how you avoid reporting a hostname you
invented from a string.

Next case: C06 opens both vhosts in a browser; C07 exploits the API you just found.
