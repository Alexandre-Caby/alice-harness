#!/usr/bin/env python3
"""No anonymous read or post; a token holder can post to a topic and read it back.

Usage: python3 test.py [ntfy URL, default http://10.50.0.80:8080] [container, default alice-ntfy]"""
import json
import os
import secrets
import subprocess
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tests"))
from owui import Report  # noqa: E402

URL = (sys.argv[1] if len(sys.argv) > 1 else "http://10.50.0.80:8080").rstrip("/")
CONTAINER = sys.argv[2] if len(sys.argv) > 2 else "alice-ntfy"


def http(path, data=None, token=None):
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    try:
        with urllib.request.urlopen(urllib.request.Request(f"{URL}{path}", data, headers), timeout=5) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, ""


def ntfy(*args, env=None):
    cmd = ["docker", "exec"] + [x for k, v in (env or {}).items() for x in ("-e", f"{k}={v}")] + [CONTAINER, "ntfy", *args]
    return subprocess.run(cmd, capture_output=True, text=True)


def main():
    t = Report("modules / ntfy")
    user, topic = f"test-{secrets.token_hex(3)}", f"test-{secrets.token_hex(4)}"
    t.check(http(f"/{topic}", b"hello")[0] in (401, 403), "posting without an account is refused")
    t.check(http(f"/{topic}/json?poll=1")[0] in (401, 403), "reading without an account is refused")
    ntfy("user", "add", user, env={"NTFY_PASSWORD": secrets.token_urlsafe(16)})
    try:
        ntfy("access", user, topic, "rw")
        token = next((w for w in ntfy("token", "add", user).stdout.split() if w.startswith("tk_")), None)
        t.check(token is not None, "a token is issued for the user")
        code, _ = http(f"/{topic}", b"approval needed", token)
        t.check(code == 200, "a user with a token can post", f"HTTP {code}")
        code, body = http(f"/{topic}/json?poll=1", token=token)
        messages = [json.loads(line).get("message") for line in body.splitlines() if line.strip()]
        t.check("approval needed" in messages, "the message can be read back")
    finally:
        ntfy("user", "del", user)
    t.done()


if __name__ == "__main__":
    main()
