# Solution — C03 (wildcard host fuzzing)

Maps to writeup para 16 and 30: wildcard certificate → enumerate subdomains → fuzz the `Host` header
with Burp Intruder → look for the response that stops being the default page.

```bash
U=https://127.0.0.1:18463

# the decoys are identical, so compare content, not just length
for h in vpn intranet owa citrix sso webmail remote files sharepoint monitor; do
  printf '%s ' "$h"; curl -sk -H "Host: $h.corp.lab" $U/ | shasum -a1 | cut -c1-12
done
# every line ends with the same hash

# a real app has things a default page does not
ffuf -u $U/chatadmin -H 'Host: FUZZ.corp.lab' -w _shared/data/vhost-labels.txt -fc 403,404
# chatadmin  [Status: 200, Size: 357]

curl -sk -H 'Host: chatadmin.corp.lab' $U/robots.txt
# User-agent: *
# Disallow: /chatadmin
```

Why `old-portal.corp.lab` (403) is not the answer: the vhost matched, but nothing is served from it.
A 403 tells you a rule exists; it does not tell you an application is there. In a report the 403 is a
lead, not a finding.

Why status alone fails: ten decoys answer 200 with exactly the same bytes. The discriminator is
behaviour on a path that only a real site would have.

Next case: C04 takes the vhost you found and does content discovery on it.
