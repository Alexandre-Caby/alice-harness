#!/usr/bin/env python3
"""From the internal network, the proxy reaches n8n's allowed sites only, never a private or internal address.

Usage: python3 test.py   (reads machine.env and versions.lock)"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(ROOT, "tests"))
from owui import Report, env_file  # noqa: E402

PROBE = r"""
import json, sys, urllib.request
def get(port, url):
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({"http": f"http://proxy:{port}", "https": f"http://proxy:{port}"}))
    try:
        return opener.open(url, timeout=15).status
    except urllib.error.HTTPError as e:
        return e.code
    except OSError:
        return "refused"
print(json.dumps({k: get(p, u) for k, p, u in json.loads(sys.argv[1])}))
"""


def main():
    m, lock = env_file("machine.env"), env_file("versions.lock")
    t = Report("security / egress")
    listed = [s.lstrip(".") for s in m.get("ALICE_EGRESS_N8N", "").split()]
    other = "example.org" if "example.com" in listed else "example.com"
    gateway = m["ALICE_NET_CORE_SUBNET"].split("/")[0].rsplit(".", 1)[0] + ".1"
    cases = [("other", 3128, f"https://{other}/"), ("private", 3128, "http://10.0.0.1/"),
             ("machine", 3128, f"http://{gateway}:11434/")] + ([("listed", 3128, f"https://{listed[0]}/")] if listed else [])
    r = subprocess.run(["docker", "run", "--rm", f"--network={m['ALICE_NET_CORE']}", "--entrypoint", "python3",
                        lock["PYTHON_IMAGE"], "-c", PROBE, json.dumps(cases)], capture_output=True, text=True)
    try:
        out = json.loads(r.stdout)
    except ValueError:
        t.check(False, "the proxy answers", (r.stderr or r.stdout)[-300:])
        t.done()
    if listed:
        t.check(out["listed"] != "refused", f"n8n reaches a site of its list ({listed[0]})", out["listed"])
    t.check(out["other"] == "refused", "a site off the list is refused", out["other"])
    t.check(out["private"] == 403, "a private address is refused", out["private"])
    t.check(out["machine"] == 403, "this machine's services are refused through the proxy", out["machine"])
    t.done()


if __name__ == "__main__":
    main()
