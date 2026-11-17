#!/usr/bin/env python3
"""WAV and browser (WebM) recordings transcribe correctly and fast; a place name is spelled right once it is in the
vocabulary file.

Usage: python3 test.py [STT URL, default http://10.50.0.50:7864] [vocabulary file to edit for the test]"""
import json
import os
import re
import sys
import time
import unicodedata
import urllib.request
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tests"))
from owui import Report  # noqa: E402

URL = (sys.argv[1] if len(sys.argv) > 1 else "http://10.50.0.50:7864").rstrip("/")
TERMS = sys.argv[2] if len(sys.argv) > 2 else None
FIXTURES = os.path.join(HERE, "..", "..", "tests", "fixtures")
SENTENCE = "Meet John Doe at the Kowalczyk office on Thursday at three."


def words(s):
    s = "".join(c for c in unicodedata.normalize("NFD", s.lower()) if unicodedata.category(c) != "Mn")
    return set(re.findall(r"[a-z]{3,}", s))


def transcribe(name, mime, streamed=False):
    boundary = uuid.uuid4().hex
    audio = open(os.path.join(FIXTURES, name), "rb").read()
    body = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{name}\"\r\n"
            f"Content-Type: {mime}\r\n\r\n").encode() + audio + f"\r\n--{boundary}--\r\n".encode()
    start = time.time()
    # Open WebUI streams its uploads: chunked, without Content-Length.
    req = urllib.request.Request(f"{URL}/v1/audio/transcriptions", iter([body]) if streamed else body,
                                 {"Content-Type": f"multipart/form-data; boundary={boundary}"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.load(r).get("text", ""), time.time() - start


def main():
    t = Report("modules / stt")
    saved = open(TERMS, encoding="utf-8").read() if TERMS and os.path.exists(TERMS) else None
    try:
        if TERMS:
            before, _ = transcribe("speech-en.wav", "audio/wav")
            print(f"  info  without the vocabulary: '{before}'")
            open(TERMS, "a", encoding="utf-8").write("\nKowalczyk\n")
        for name, mime in (("speech-en.wav", "audio/wav"), ("speech-en.webm", "audio/webm")):
            text, seconds = transcribe(name, mime)
            share = len(words(SENTENCE) & words(text)) / len(words(SENTENCE))
            t.check(share >= 0.85, f"{name} is transcribed", f"'{text}'")
            t.check(seconds < 5, f"{name} in under 5 s", f"{seconds:.1f} s")
        if TERMS:
            t.check("Kowalczyk" in text, "a name from the vocabulary file is spelled right")
        text, _ = transcribe("speech-en.wav", "audio/wav", streamed=True)
        t.check(len(words(SENTENCE) & words(text)) / len(words(SENTENCE)) >= 0.85,
                "a streamed upload, as Open WebUI sends it, is transcribed", f"'{text}'")
    finally:
        if TERMS:
            if saved is None:
                os.remove(TERMS)
            else:
                open(TERMS, "w", encoding="utf-8").write(saved)
    t.done()


if __name__ == "__main__":
    main()
