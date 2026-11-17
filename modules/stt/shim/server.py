#!/usr/bin/env python3
"""OpenAI-compatible POST /v1/audio/transcriptions in front of NeMo-Speech's chat endpoint.

Input is converted to 16 kHz mono WAV. Long audio is cut at silences into pieces of about a minute, transcribed a few
at a time: one request for a long recording outlasts any sensible timeout. TERMS (reread per request) is passed as
context terms, so the model spells names it can't guess.

Env: UPSTREAM (http://stt-model:8080), LANGUAGE (English), TERMS (/terms/terms.txt), LISTEN (0.0.0.0:7864).
"""
import base64
import email.parser
import email.policy
import io
import json
import os
import re
import subprocess
import tempfile
import urllib.request
import wave
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

UPSTREAM = os.environ.get("UPSTREAM", "http://stt-model:8080").rstrip("/")
LANGUAGE = os.environ.get("LANGUAGE", "English")
TERMS = os.environ.get("TERMS", "/terms/terms.txt")
LISTEN = os.environ.get("LISTEN", "0.0.0.0:7864")
MAX_BODY = 100 * 1024 * 1024
PIECE, SLACK, WORKERS = 60, 15, 4  # seconds per piece, how far to look for a silence, pieces at once


def instruction():
    try:
        terms = " ".join(open(TERMS, encoding="utf-8").read().split())
    except OSError:
        terms = ""
    return (f"Transcribe with punctuation and capitalization. The speech is in {LANGUAGE}."
            + (f" Context terms: {terms}" if terms else ""))


def to_wav(data):
    with tempfile.TemporaryDirectory() as d:
        src, dst = os.path.join(d, "in"), os.path.join(d, "out.wav")
        open(src, "wb").write(data)
        r = subprocess.run(["ffmpeg", "-nostdin", "-y", "-i", src, "-ac", "1", "-ar", "16000", dst], capture_output=True)
        if r.returncode != 0:
            raise ValueError("unreadable audio")
        return open(dst, "rb").read()


def pieces(wav):
    """Cut points at the middle of a silence near every PIECE seconds, or at PIECE + SLACK without one."""
    with wave.open(io.BytesIO(wav)) as w:
        rate, frames = w.getframerate(), w.readframes(w.getnframes())
    total = len(frames) / (2 * rate)  # 16-bit mono
    if total <= PIECE + SLACK:
        return [wav]
    with tempfile.NamedTemporaryFile(suffix=".wav") as f:
        f.write(wav)
        f.flush()
        log = subprocess.run(["ffmpeg", "-nostdin", "-i", f.name, "-af", "silencedetect=noise=-35dB:d=0.3", "-f", "null", "-"],
                             capture_output=True, text=True).stderr
    starts = [float(x) for x in re.findall(r"silence_start: ([\d.]+)", log)]
    ends = [float(x) for x in re.findall(r"silence_end: ([\d.]+)", log)]
    middles = [(a + b) / 2 for a, b in zip(starts, ends)]
    cuts, last = [], 0.0
    while total - last > PIECE + SLACK:
        near = [m for m in middles if last + PIECE - SLACK <= m <= last + PIECE + SLACK]
        last = min(near, key=lambda m: abs(m - last - PIECE)) if near else last + PIECE + SLACK
        cuts.append(last)
    out = []
    for a, b in zip([0.0] + cuts, cuts + [total]):
        buf = io.BytesIO()
        with wave.open(buf, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(rate)
            w.writeframes(frames[int(a * rate) * 2:int(b * rate) * 2])
        out.append(buf.getvalue())
    return out


def transcribe_all(wav):
    with ThreadPoolExecutor(WORKERS) as pool:
        return " ".join(t for t in pool.map(transcribe, pieces(wav)) if t)


def transcribe(wav):
    body = {"model": "salm", "temperature": 0, "messages": [{"role": "user", "content": [
        {"type": "text", "text": instruction()},
        {"type": "input_audio", "input_audio": {"data": base64.b64encode(wav).decode(), "format": "wav"}}]}]}
    req = urllib.request.Request(f"{UPSTREAM}/v1/chat/completions", json.dumps(body).encode(), {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return " ".join(json.load(r)["choices"][0]["message"]["content"].split())


def audio_part(content_type, body):
    message = email.parser.BytesParser(policy=email.policy.HTTP).parsebytes(
        f"Content-Type: {content_type}\r\n\r\n".encode() + body)
    for part in message.iter_parts():
        if part.get_param("name", header="content-disposition") == "file":
            return part.get_payload(decode=True)
    raise ValueError("no file field")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, status, payload):
        data = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def body(self):
        """Open WebUI streams the upload (chunked, no Content-Length)."""
        if "chunked" in self.headers.get("Transfer-Encoding", "").lower():
            data = b""
            while size := int(self.rfile.readline().split(b";")[0].strip() or b"0", 16):
                data += self.rfile.read(size)
                self.rfile.readline()
                if len(data) > MAX_BODY:
                    raise ValueError("request too large")
            while self.rfile.readline().strip():
                pass
        else:
            size = int(self.headers.get("Content-Length") or 0)
            if not 0 < size <= MAX_BODY:
                raise ValueError("request size out of bounds")
            data = self.rfile.read(size)
        if not data:
            raise ValueError("empty request")
        return data

    def do_GET(self):
        self.reply(200, {"ok": True}) if self.path == "/health" else self.reply(404, {"error": "not found"})

    def do_POST(self):
        if self.path.rstrip("/") != "/v1/audio/transcriptions":
            return self.reply(404, {"error": "not found"})
        try:
            text = transcribe_all(to_wav(audio_part(self.headers.get("Content-Type", ""), self.body())))
            self.reply(200, {"text": text})
        except ValueError as e:
            self.reply(400, {"error": str(e)})
        except OSError:
            self.reply(502, {"error": "speech model unreachable"})


if __name__ == "__main__":
    host, port = LISTEN.rsplit(":", 1)
    ThreadingHTTPServer((host, int(port)), Handler).serve_forever()
