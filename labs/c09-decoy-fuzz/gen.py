#!/usr/bin/env python3
"""Generate the C09 lab data: 40 vhosts, 1 real, decoys with lures and catch-alls.

Deterministic: run it again and the tree is identical. Outputs:
  edge/sites.json           routing table for the gateway
  sites/vhosts/<name>/...   identical default pages (+ the real app tree)
  sites/nginx.conf          catch-all aware config
"""
from __future__ import annotations

import json
import pathlib
import shutil

LAB = pathlib.Path(__file__).resolve().parent
ROOT = LAB.parent.parent
REAL = "chatadmin.corp.lab"
LURES = ["vpn", "intranet", "owa", "citrix", "sso", "webmail", "remote", "files"]
CATCHALL = ["monitor", "status"]
IP = "172.28.90.20"
SUBNET = 90

labels = (ROOT / "_shared/data/vhost-labels.txt").read_text().split()
decoys = [w for w in labels if w != "chatadmin"]
decoys += [f"app{i:02d}" for i in range(1, 17)]
decoys = decoys[:39]
assert len(decoys) == 39, len(decoys)

vhosts = LAB / "sites/vhosts"
if vhosts.exists():
    shutil.rmtree(vhosts)
vhosts.mkdir(parents=True)

DEFAULT_PAGE = (ROOT / "labs/c01-bare-ip-404/sites/iis/index.html").read_text()
ERROR_PAGE = (ROOT / "labs/c01-bare-ip-404/sites/iis/404.html").read_text()
(vhosts / "404.html").write_text(ERROR_PAGE)

# the real site
real = vhosts / "real"
(real / "app").mkdir(parents=True)
(real / "index.html").write_text(DEFAULT_PAGE)
(real / "robots.txt").write_text("User-agent: *\nDisallow: /app\n")
(real / "app" / "index.html").write_text(
    "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>Chat Admin</title></head>"
    "<body><div id=\"app\">Chat Admin — internal console.</div></body></html>\n"
)

# every decoy gets byte-identical content
for name in decoys:
    d = vhosts / f"d-{name}"
    d.mkdir()
    (d / "index.html").write_text(DEFAULT_PAGE)
    if name in CATCHALL:
        (d / "catchall.html").write_text(DEFAULT_PAGE)

sites = [
    {
        "host": REAL,
        "upstream": f"http://{IP}:80",
        "server": "Microsoft-IIS/10.0",
        "case_insensitive": True,
        "paths": [
            {"prefix": "/app/", "upstream": f"http://{IP}:80", "rewrite": "/real/app/"},
            {"prefix": "/app", "upstream": f"http://{IP}:80", "rewrite": "/real/app/index.html"},
            {"prefix": "/", "upstream": f"http://{IP}:80", "rewrite": "/real/"},
        ],
    }
]

for name in decoys:
    rule: dict[str, object] = {
        "host": f"{name}.corp.lab",
        "upstream": f"http://{IP}:80",
        "server": "Microsoft-IIS/10.0",
    }
    if name in CATCHALL:
        # answers 200 to every path: the false-positive generator
        rule["paths"] = [{"prefix": "/", "upstream": f"http://{IP}:80",
                          "rewrite": f"/d-{name}/catchall.html", "drop_path": True}]
    else:
        rule["paths"] = [{"prefix": "/", "upstream": f"http://{IP}:80",
                          "rewrite": f"/d-{name}/"}]
    if name in LURES:
        rule["app_header"] = {"X-Forwarded-Host": REAL, "X-Backend": "chatadmin"}
    sites.append(rule)

cfg = {
    "http_addr": ":8080",
    "https_addr": ":8443",
    "cert_file": "/certs/lab.crt",
    "key_file": "/certs/lab.key",
    "default_server": "Microsoft-HTTPAPI/2.0",
    "sites": sites,
}
(LAB / "edge/sites.json").write_text(json.dumps(cfg, indent=2) + "\n")

nginx = """server {
    listen 80 default_server;
    server_name _;
    root /vhosts;
    index index.html;
    server_tokens off;
    autoindex off;
    error_page 404 /404.html;
    location = /404.html { internal; }
    location ~ /\\. { deny all; }
    location / { try_files $uri $uri/ =404; }
}
"""
(LAB / "sites/nginx.conf").write_text(nginx)

print(f"generated: 1 real + {len(decoys)} decoys "
      f"({len(LURES)} lures, {len(CATCHALL)} catch-alls)")
