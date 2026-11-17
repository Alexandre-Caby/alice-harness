#!/usr/bin/env python3
"""Usage: python3 test.py [n8n URL, default http://10.50.0.70:5678] [container, default alice-n8n]"""
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
sys.path.insert(0, os.path.join(ROOT, "tests"))
from owui import Report  # noqa: E402

URL = (sys.argv[1] if len(sys.argv) > 1 else "http://10.50.0.70:5678").rstrip("/")
CONTAINER = sys.argv[2] if len(sys.argv) > 2 else "alice-n8n"


def status(path):
    try:
        return urllib.request.urlopen(f"{URL}{path}", timeout=5).status
    except urllib.error.HTTPError as e:
        return e.code


def main():
    t = Report("modules / n8n")
    lock = dict(l.strip().split("=", 1) for l in open(os.path.join(ROOT, "versions.lock")) if "=" in l and not l.startswith("#"))
    want = lock["N8N_IMAGE"].split("@")[0].rsplit(":", 1)[1]
    t.check(json.load(urllib.request.urlopen(f"{URL}/healthz", timeout=5)).get("status") == "ok", "n8n answers")
    version = subprocess.run(["docker", "exec", CONTAINER, "n8n", "--version"], capture_output=True, text=True).stdout.strip()
    t.check(version == want, "the pinned n8n version runs", version)
    t.check(status("/rest/workflows") == 401, "workflows are not readable without an account")
    t.done()


if __name__ == "__main__":
    main()
