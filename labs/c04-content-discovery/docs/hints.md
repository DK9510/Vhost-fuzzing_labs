# Hints — C04

1. Measure the baseline: request a path that cannot exist, record status **and** length.
2. `ffuf -u https://127.0.0.1:18473/FUZZ -H 'Host: chatadmin.corp.lab' -w <raft> -fs <baseline> -fc 403`
3. Two hits are expected to be noise: the 403 backup tree, and the site's own error page. Filter
   them rather than chasing them.
4. The application root is a directory with an `index.html`; the gateway serves it without a
   redirect, so `/chatadmin` and `/chatadmin/` are both 200.
5. Read the shell's `<script src>` — the next case starts there.
