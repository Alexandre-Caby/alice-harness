#!/usr/bin/env python3
"""Image requests as Open WebUI sends them: right size, fast, no fixed seed, and edits work.

Usage: python3 test.py [images URL, default http://10.50.0.60:7860]"""
import base64
import hashlib
import json
import os
import struct
import sys
import time
import urllib.request
import uuid

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tests"))
from owui import Report  # noqa: E402

URL = (sys.argv[1] if len(sys.argv) > 1 else "http://10.50.0.60:7860").rstrip("/")
PROMPT = "A ginger cat sitting on a rooftop at sunset, warm light, photo"


def generate(size="512x512"):
    body = json.dumps({"model": "sd-cpp-local", "prompt": PROMPT, "size": size, "n": 1, "response_format": "b64_json"}).encode()
    start = time.time()
    req = urllib.request.Request(f"{URL}/v1/images/generations", body, {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=300) as r:
        image = base64.b64decode(json.load(r)["data"][0]["b64_json"])
    return image, time.time() - start


def size_of(png):
    return struct.unpack(">II", png[16:24]) if png[:8] == b"\x89PNG\r\n\x1a\n" else None


def edit(png):
    boundary = uuid.uuid4().hex
    fields = {"model": "sd-cpp-local", "prompt": "the same cat under a stormy sky", "size": "512x512", "response_format": "b64_json"}
    body = b"".join(f"--{boundary}\r\nContent-Disposition: form-data; name=\"{k}\"\r\n\r\n{v}\r\n".encode() for k, v in fields.items())
    body += (f"--{boundary}\r\nContent-Disposition: form-data; name=\"image\"; filename=\"cat.png\"\r\n"
             f"Content-Type: image/png\r\n\r\n").encode() + png + f"\r\n--{boundary}--\r\n".encode()
    req = urllib.request.Request(f"{URL}/v1/images/edits", body, {"Content-Type": f"multipart/form-data; boundary={boundary}"})
    with urllib.request.urlopen(req, timeout=300) as r:
        return base64.b64decode(json.load(r)["data"][0]["b64_json"])


def main():
    t = Report("modules / images")
    first, seconds = generate()
    t.check(size_of(first) == (512, 512), "an image of the requested size comes back", str(size_of(first)))
    t.check(seconds < 30, "a 512×512 image in under 30 s", f"{seconds:.0f} s")
    second, _ = generate()
    t.check(hashlib.sha256(first).digest() != hashlib.sha256(second).digest(), "the same request twice gives two different images")
    edited = edit(first)
    t.check(size_of(edited) is not None and edited != first, "an existing image can be edited")
    t.done()


if __name__ == "__main__":
    main()
