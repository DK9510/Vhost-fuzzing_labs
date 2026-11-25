# Solution — C04 (content discovery)

Maps to writeup para 32-42: "no result on passive endpoint discovery via wayback/gau, so the only
option was active content discovery... Seclists raft-large-directories-lowercase... found the
application on /chatadmin".

```bash
H='Host: chatadmin.corp.lab'; U=https://127.0.0.1:18473

# baseline
curl -sk -o /dev/null -w '%{http_code} %{size_download}\n' -H "$H" $U/definitely-not-here
# 404 1232

# discovery
ffuf -u $U/FUZZ -H "$H" -w raft-large-directories-lowercase.txt -fs 1232 -fc 403 -t 100
# chatadmin   [Status: 200, Size: 357]

curl -sk -H "$H" $U/chatadmin        # SPA shell
curl -sk -H "$H" $U/chatadmin/assets/app.js
# window.__ENV = { API_BASE: "https://chat-api.corp.lab/api" };
```

Why `-fs 1232`: every miss returns the site's IIS 404 page, which is a fixed 1 232 bytes. Filtering
on the measured baseline removes ~56 000 identical responses instead of reading them.

Why not `/chatadmin.backup`: 403 means the vhost knows the path and refuses it. It is a lead to
keep, not an application root.

## Next case

C05 takes the bundle you just read and pivots to the second vhost it names.
