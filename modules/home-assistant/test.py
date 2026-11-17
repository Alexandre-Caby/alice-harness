#!/usr/bin/env python3
"""Home Assistant answers, and the allow-list only passes its MCP tools that read or switch something on or off.

Usage: python3 test.py   (reads machine.env and versions.lock)"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(ROOT, "tests"))
from owui import Report, env_file  # noqa: E402

# Device control tools that only read, or that the opposite action undoes.
SAFE = {"homeassistant__GetLiveContext", "llm__GetDateTime", "todo__get_items", "intent__HassTurnOn",
        "intent__HassTurnOff", "todo__HassListAddItem", "todo__HassListCompleteItem"}
PROBE = """
import urllib.error, urllib.request
try:
    urllib.request.urlopen("http://home-assistant:8123/api/", timeout=10)
    print("open")
except urllib.error.HTTPError as e:
    print(e.code)
"""


def main():
    m, lock = env_file("machine.env"), env_file("versions.lock")
    t = Report("modules / home-assistant")
    r = subprocess.run(["docker", "run", "--rm", f"--network={m['ALICE_NET_CORE']}", "--entrypoint", "python3",
                        lock["PYTHON_IMAGE"], "-c", PROBE], capture_output=True, text=True)
    ok = r.stdout.strip() == "401"
    t.check(ok, "Home Assistant answers and asks for a token", "" if ok else (r.stdout + r.stderr)[-200:])
    entries = [line.split("#", 1)[0].strip() for line in open(os.path.join(ROOT, "modules", "decision", "allowlist.txt"))]
    ours = [e.split("_", 1)[1] for e in entries if e.startswith("*_") and "__" in e]
    t.check(bool(ours) and set(ours) <= SAFE, "only reads and on/off actions of Home Assistant pass without approval",
            ", ".join(sorted(set(ours) - SAFE)))
    t.done()


if __name__ == "__main__":
    main()
