# Solution — C11 (silent SNI/Host gate)

```bash
H=https://127.0.0.1:18553; P=http://127.0.0.1:18190; GOOD=ops.corp.lab

# 1. bare IP: no SNI (curl sends none for an IP)
curl -sk --max-time 4 -o /dev/null -w '%{http_code}\n' $H/ ; echo "rc=$?"
# 000
# rc=28        <- the only observable: your own timeout

# 2. wrong SNI
curl -sk --max-time 4 -o /dev/null -w '%{http_code}\n' \
  --resolve unknown.corp.lab:18553:127.0.0.1 https://unknown.corp.lab:18553/ ; echo "rc=$?"
# 000 / rc=28

# 3. correct SNI, wrong Host: handshake completes, the request is dropped
curl -sk --max-time 4 -o /dev/null -w '%{http_code}\n' \
  --resolve $GOOD:18553:127.0.0.1 https://$GOOD:18553/ -H 'Host: chatadmin.corp.lab' ; echo "rc=$?"
# 000 / rc=28

# 4. plain HTTP at the IP (curl sends Host: 127.0.0.1:18190)
curl -s --max-time 4 -o /dev/null -w '%{http_code}\n' $P/ ; echo "rc=$?"
# 000 / rc=28

# 5. no certificate is offered without SNI
timeout 6 openssl s_client -connect 127.0.0.1:18553 </dev/null 2>/dev/null | grep -c 'BEGIN CERTIFICATE'
# 0

# 6. the only way in: SNI and Host both correct
curl -sk --max-time 6 --resolve $GOOD:18553:127.0.0.1 https://$GOOD:18553/ | grep -E 'Ops Console|FLAG'
# <h1>Ops Console</h1>
# Console bootstrap token: FLAG{sni_and_host_or_no_answer}

curl -sk --max-time 6 -H 'Host: ops.corp.lab' $P/health
# {"service":"ops-console","status":"ok","zone":"corp.lab"}

# 7. the allow-list is literal
curl -sk --max-time 6 -o /dev/null -w '%{http_code}\n' --resolve $GOOD:18553:127.0.0.1 \
  https://$GOOD:18553/ -H "Host: $GOOD:443"      # 200 - port is removed
curl -sk --max-time 4 -o /dev/null -w '%{http_code}\n' --resolve $GOOD:18553:127.0.0.1 \
  https://$GOOD:18553/ -H "Host: $GOOD."          # 000 - trailing dot is not normalised
```

How the name would actually be found (this lab hands it to you):

- `:80` has no SNI, so Host fuzzing there is the cheapest probe — a silence/mismatch split tells you a
  name exists even when nothing answers.
- Certificate transparency, JS bundles, DNS history or a sibling vhost leak the name. Passive
  certificate grabs fail here by design: without SNI there is no certificate to grab.
- Once you have a candidate, SNI-probe it: `openssl s_client -servername <candidate>` returning a full
  handshake proves the front end knows the name.

Why it matters operationally:

| Observation | What it means |
|---|---|
| timeout (rc 28), no bytes | silent drop — a rule exists and refused you, or no rule matched |
| 404 + a platform banner | a router answered; the vhost is unknown to it |
| 403 | a rule matched and refused (C03/C09/C10 bait) |
| TCP reset | a firewall rejected the flow; the host may not be listening at all |

Consequences for tooling: ffuf/nuclei need `-timeout`/`-timeout 3` and low concurrency, or one silent
host stalls the whole run; Burp shows "connection closed" with no response to forward; a scanner that
grades on status codes records nothing. "No finding" from silence is a tooling artefact, not evidence
of absence — and a silent front end is exactly how internal-only apps stay hidden.

Grading: the check asserts timeout (rc 28) for no-SNI, wrong-SNI, wrong-Host, bare-IP HTTP and
empty-Host; zero certificates without SNI; 200 + flag with both names correct; Server `OpsGate/1.0`;
port-tolerant and dot-intolerant allow-list; and the wildcard certificate still in play.
