#!/usr/bin/env python3
"""A receipt photo sent the way Open WebUI does (PUT /tika/json/md): words and amounts come back, fast.

Usage: python3 test.py [OCR URL, default http://10.50.0.30:9998]"""
import json
import os
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tests"))
from owui import Report  # noqa: E402

URL = (sys.argv[1] if len(sys.argv) > 1 else "http://10.50.0.30:9998").rstrip("/")


def main():
    t = Report("modules / ocr")
    photo = open(os.path.join(HERE, "..", "..", "tests", "fixtures", "receipt.png"), "rb").read()
    start = time.time()
    req = urllib.request.Request(f"{URL}/tika/json/md", photo, {"Content-Type": "image/png"}, method="PUT")
    with urllib.request.urlopen(req, timeout=60) as r:
        text = json.load(r).get("tk:content", "")
    seconds = time.time() - start
    t.check("GREEN VALLEY MARKET" in text, "the heading is read", " ".join(text.split())[:60])
    t.check("23.47" in text and "Cheddar cheese" in text, "amounts and words are read")
    t.check(seconds < 10, "a photo is read in under 10 s", f"{seconds:.1f} s")
    t.done()


if __name__ == "__main__":
    main()
