# C07 — Django DEBUG=True + broken SMTP → reset token → admin

**Case:** C7 (writeup para 56-67). **Ports:** 18140 / 18503. **Time:** 35 min.
This is the exploit case: the whole writeup chain lands here.

## Objective

Trigger an error in the password-reset flow, read the technical 500 page, and take admin.

## What you get

- `chat-api.corp.lab` → DRF API, `DEBUG=True` (JSON only, no browsable renderer), SMTP pointed at a
  port where nothing listens.
- `chatadmin.corp.lab` → the console shell with a reset form.

## Success criterion

`bash checks/verify.sh`. As a human: you hold an admin JWT and the flag from `/api/chats`.

## Hints

1. `POST /api/auth/password_reset {"email":"admin@corp.lab"}` — status?
2. The page is ~127 KB. Do not paste it into a chat window; `grep -oE 'token=[0-9a-f]{32}'`.
3. The token is single use. `POST /api/auth/password_reset/confirm {"token":"…","password":"…"}`.
4. Then `POST /api/auth/login`, and use the JWT as `Authorization: Bearer`.
5. The flag is in a chat only an admin can read; an agent account must not see it.
