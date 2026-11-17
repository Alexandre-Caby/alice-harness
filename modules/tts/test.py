#!/usr/bin/env python3
"""TTS requests as Open WebUI sends them (escaped JSON, a voice name). With an STT URL, the audio is transcribed back
and compared.

Usage: python3 test.py [TTS URL, default http://10.50.0.40:7863] [STT URL, optional]"""
import json
import os
import re
import struct
import sys
import time
import unicodedata
import urllib.request
import uuid

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tests"))
from owui import Report  # noqa: E402

URL = (sys.argv[1] if len(sys.argv) > 1 else "http://10.50.0.40:7863").rstrip("/")
STT = sys.argv[2].rstrip("/") if len(sys.argv) > 2 else None
SENTENCE = "Please remind Zoë and José that the café meeting moved to Friday."


def words(s):
    s = "".join(c for c in unicodedata.normalize("NFD", s.lower()) if unicodedata.category(c) != "Mn")
    return set(re.findall(r"[a-z]{3,}", s))


def transcribe(audio):
    boundary = uuid.uuid4().hex
    body = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"language\"\r\n\r\nen\r\n"
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\n"
            f"Content-Type: audio/wav\r\n\r\n").encode() + audio + f"\r\n--{boundary}--\r\n".encode()
    req = urllib.request.Request(f"{STT}/v1/audio/transcriptions", body,
                                 {"Content-Type": f"multipart/form-data; boundary={boundary}"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.load(r).get("text", "")


def main():
    t = Report("modules / tts")
    body = json.dumps({"input": SENTENCE, "voice": "alice", "model": "qwen3-tts"}).encode()  # ASCII-escaped, like Open WebUI
    start = time.time()
    req = urllib.request.Request(f"{URL}/v1/audio/speech", body, {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        audio = r.read()
    seconds = time.time() - start
    ok = audio[:4] == b"RIFF" and audio[8:12] == b"WAVE"
    t.check(ok, "a WAV file comes back for any voice name")
    if ok:
        rate = struct.unpack("<I", audio[24:28])[0]
        duration = (len(audio) - 44) / (rate * 2)
        t.check(2 < duration < 12, "the speech has a plausible length", f"{duration:.1f} s")
    t.check(seconds < 10, "speech is ready in under 10 s", f"{seconds:.1f} s")
    if STT and ok:
        heard = transcribe(audio)
        share = len(words(SENTENCE) & words(heard)) / len(words(SENTENCE))
        t.check(share >= 0.9, "accented words are spoken correctly (heard back by speech-to-text)", f"'{heard}'")
    t.done()


if __name__ == "__main__":
    main()
