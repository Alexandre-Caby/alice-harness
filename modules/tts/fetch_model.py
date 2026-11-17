#!/usr/bin/env python3
"""Usage: fetch_model.py REPO REVISION SHA256_OF_MODEL DEST"""
import hashlib
import json
import os
import socket
import sys
import urllib.request

repo, revision, model_sha, dest = sys.argv[1:5]
socket.setdefaulttimeout(120)  # a stalled download fails instead of hanging


def tree(path=""):
    url = f"https://huggingface.co/api/models/{repo}/tree/{revision}" + (f"/{path}" if path else "")
    with urllib.request.urlopen(url, timeout=60) as r:
        for entry in json.load(r):
            if entry["type"] == "directory":
                yield from tree(entry["path"])
            else:
                yield entry["path"]


for path in tree():
    target = os.path.join(dest, path)
    if os.path.exists(target):
        continue
    os.makedirs(os.path.dirname(target), exist_ok=True)
    urllib.request.urlretrieve(f"https://huggingface.co/{repo}/resolve/{revision}/{path}", target + ".part")
    os.replace(target + ".part", target)

digest = hashlib.sha256()
with open(os.path.join(dest, "model.safetensors"), "rb") as f:
    for block in iter(lambda: f.read(1 << 20), b""):
        digest.update(block)
if digest.hexdigest() != model_sha:
    os.remove(os.path.join(dest, "model.safetensors"))
    sys.exit("model.safetensors hash mismatch")
