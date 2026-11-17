#!/usr/bin/env python3
"""Usage: python3 test.py [Ollama URL, default http://127.0.0.1:11434]"""
import json
import os
import subprocess
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(ROOT, "tests"))
from owui import Report, env_file  # noqa: E402

URL = (sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:11434").rstrip("/")


def main():
    t = Report("core / ollama")
    lock, machine = env_file("versions.lock"), env_file("machine.env")
    if machine.get("ALICE_OLLAMA_MODE") == "native":
        version = json.load(urllib.request.urlopen(f"{URL}/api/version", timeout=5))["version"]
        t.check(version == lock["OLLAMA_VERSION"], "the pinned Ollama version runs", version)
        out = subprocess.run(["systemctl", "show", "ollama", "-p", "Environment", "--value"], capture_output=True, text=True).stdout
        env = dict(v.split("=", 1) for v in out.split() if "=" in v)
        wanted = {k: machine[f"ALICE_{k}"] for k in ("OLLAMA_MAX_LOADED_MODELS", "OLLAMA_NUM_PARALLEL")}
        wanted["OLLAMA_CONTEXT_LENGTH"] = machine.get("ALICE_OLLAMA_CONTEXT_LENGTH", "65536")
        for key, want in wanted.items():
            t.check(env.get(key) == want, f"{key} is {want}", env.get(key, "unset"))
    have = {m["name"] for m in json.load(urllib.request.urlopen(f"{URL}/api/tags", timeout=5))["models"]}
    wanted = {"bge-m3:latest"} | {p.split("=", 1)[1].split("|")[0] for p in machine["ALICE_PRESETS"].split(";") if p}
    missing = sorted(m for m in wanted if m not in have and f"{m}:latest" not in have)
    t.check(not missing, "every preset model is present", ", ".join(missing))
    t.done()


if __name__ == "__main__":
    main()
