# Solution — C09 (decoys)

```bash
U=https://127.0.0.1:18523
HOSTS=$(jq -r '.sites[].host' labs/c09-decoy-fuzz/edge/sites.json)

for h in $HOSTS; do
  b=$(curl -sk -H "Host: $h" $U/app)
  case "$b" in *"Chat Admin"*) echo "HIT $h";; esac
done
# HIT chatadmin.corp.lab
```

Why each trap fails:

| Trap | What it does | Why it is not a hit |
|---|---|---|
| catch-all (`monitor`, `status`) | 200 on `/app`, `/anything` | body is the default page, no app marker |
| lures (`vpn`, `intranet`, …) | `X-Forwarded-Host: chatadmin.corp.lab` | header is attacker-visible metadata; the body is the decoy page |
| identical roots | same bytes, same length | status/length/shape triage cannot separate them |
| one 403-style bait in C03 | rule matched, nothing served | a matched rule is a lead, not an application |

The operational rule: **a vhost finding is a body/behaviour claim, supported by two paths.** Anything
that rests on one 200, one header, or one length difference is the kind of thing that gets a bug
report closed as informational.

Grading: the check asserts exactly one true hit, ≥2 catch-alls answering 200, 8 lures echoing the real
host, 39 identical roots, and no hit outside the real host. Re-running the generator is deterministic.
