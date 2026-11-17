#!/usr/bin/env python3
"""Decision adapter: answers Open WebUI approval requests (POST /v1/decisions) with a System One model on llama.cpp.

Each allowed call is scored against CRITERIA; approval is required when any score reaches the threshold. Tools marked
"pass" in the allow-list run without a model call (what the workspace wall and the server already make harmless).
Calls outside the allow-list, fetches of sites the user never named and malformed requests ask without a model call.
Any error returns an error status, which Open WebUI treats as "ask".

Env: LISTEN (0.0.0.0:8096), UPSTREAM (http://decision-model:8080), MODEL (decision), ALLOWLIST, LOG.
"""
import fnmatch
import json
import math
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LISTEN = os.environ.get("LISTEN", "0.0.0.0:8096")
UPSTREAM = os.environ.get("UPSTREAM", "http://decision-model:8080").rstrip("/")
MODEL = os.environ.get("MODEL", "decision")
ALLOWLIST = os.environ.get("ALLOWLIST", os.path.join(os.path.dirname(os.path.abspath(__file__)), "allowlist.txt"))
LOG = os.environ.get("LOG", "/state/decisions.jsonl")
APPROVAL_QUESTION = "requires_confirmation"
MAX_BODY = 256 * 1024
UPSTREAM_TIMEOUT = 14  # under Open WebUI's 15 s timeout (approval.patch)
CRITERIA = {
    "deletes": "Does this call permanently delete files, folders or data?",
    "unrequested_change": "Does this call overwrite or modify files or data that the user did not ask to change?",
    "data_out": "Does this call send the user's files or personal information off this server: to the internet, by e-mail "
                "or message, or to another person? Sending them to this server's own services (speech-to-text, voice, "
                "OCR, images) does not count.",
    "secrets": "Does this call read, store or reveal passwords, keys, system secrets, bank details or private codes?",
    "system": "Does this call install software, change permissions or system settings, or risk exhausting the machine?",
    "memory_source": "Is this call saving to memory something the user did not say about themselves?",
}


class Rejected(Exception):
    pass


def allowlist():
    """Entry -> True when marked "pass". Reread on every request: edits apply without a restart."""
    entries = {}
    try:
        with open(ALLOWLIST, encoding="utf-8") as f:
            for line in f:
                words = line.split("#", 1)[0].split()
                if words:
                    entries[words[0]] = words[1:] == ["pass"]
    except OSError:
        pass
    return entries


def listed(tool):
    """None when not listed, "pass" or "judge". One * may stand for the per-person part of a name (e.g. their own n8n
    connection); a tool matching both kinds of entry is judged."""
    marks = [p for entry, p in allowlist().items() if fnmatch.fnmatchcase(tool, entry)]
    return None if not marks else "pass" if all(marks) else "judge"


def tool_name(evidence):
    try:
        name = json.loads(evidence)["tool"]["name"]
        return name if isinstance(name, str) and name else None
    except (ValueError, TypeError, KeyError):
        return None


# Prefix of the message Open WebUI injects with a background task's result.
BACKGROUND_RESULT = "[ASYNC SUBAGENT COMPLETE"


def site_named_by_user(evidence):
    """Block exfiltration URLs planted by read content, and data smuggled into the query of a named site.

        The host and any query string must appear in the user's own messages. Background task results arrive as user
        messages but carry web content, so they don't count."""
    try:
        d = json.loads(evidence)
        url = urllib.parse.urlsplit(str(d["arguments"]["url"]))
        host = (url.hostname or "").lower().removeprefix("www.")
        messages = [str(d.get("user_request") or "")] + [str(m) for m in d.get("recent_user_messages") or []]
        said = " ".join(m for m in messages if not m.startswith(BACKGROUND_RESULT)).lower()
    except (ValueError, TypeError, KeyError, AttributeError):
        return False
    return bool(host) and host in said and (not url.query or url.query.lower() in said)


CONDITIONS = {"fetch_url": site_named_by_user}


def ask_model(evidence, questions):
    body = {"model": MODEL, "state": evidence,
            "questions": {n: {"type": "noul", "instructions": text} for n, text in questions.items()}}
    req = urllib.request.Request(f"{UPSTREAM}/v1/systemone", json.dumps(body).encode(), {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=UPSTREAM_TIMEOUT) as r:
        answer = json.load(r)
    answers = answer.get("answers") if isinstance(answer, dict) else None
    if not isinstance(answers, dict):
        raise Rejected("model answer has no 'answers'")
    out = {}
    for n in questions:
        p = (answers.get(n) or {}).get("noul")
        if type(p) not in (int, float) or not math.isfinite(p) or not 0 <= p <= 1:
            raise Rejected(f"invalid probability for {n}")
        out[n] = float(p)
    return out


def decide(body):
    questions = body.get("questions")
    evidence = body.get("input")
    if not isinstance(questions, list) or not questions or not isinstance(evidence, str):
        raise Rejected("malformed request")
    texts = {}
    for q in questions:
        if not isinstance(q, dict) or q.get("type") != "predicate" or not isinstance(q.get("name"), str):
            raise Rejected("only named predicate questions are supported")
        if q["name"] in texts:
            raise Rejected("duplicate question")
        texts[q["name"]] = str(q.get("instructions") or "")
    trace = {"questions": len(texts)}
    probabilities = {}
    if APPROVAL_QUESTION in texts:
        tool = tool_name(evidence)
        trace["tool"] = tool
        condition = CONDITIONS.get(tool)
        del texts[APPROVAL_QUESTION]
        kind = listed(tool) if tool else None
        if kind is None or (condition and not condition(evidence)):
            probabilities[APPROVAL_QUESTION] = 1.0
            trace["origin"] = "floor"
        elif kind == "pass":
            probabilities[APPROVAL_QUESTION] = 0.0
            trace["origin"] = "pass"
        else:
            scores = ask_model(evidence, CRITERIA)
            top = max(scores, key=scores.get)
            probabilities[APPROVAL_QUESTION] = scores[top]
            trace.update(origin="model", criterion=top)
    if texts:
        probabilities.update(ask_model(evidence, texts))
        trace.setdefault("origin", "model")
    trace["probabilities"] = {n: round(p, 4) for n, p in probabilities.items()}
    answers = [{"name": q["name"], "type": "predicate", "probability": probabilities[q["name"]]} for q in questions]
    return {"object": "decision", "model": body.get("model") or MODEL, "answers": answers}, trace


def log(line):
    try:
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(json.dumps(line, ensure_ascii=False) + "\n")
    except OSError:
        pass


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

    def do_GET(self):
        if self.path == "/health":
            return self.reply(200, {"ok": True, "tools_judged_by_model": len(allowlist())})
        self.reply(404, {"error": "not found"})

    def do_POST(self):
        start = time.time()
        line = {"t": round(start, 3)}
        try:
            if self.path.rstrip("/") != "/v1/decisions":
                return self.reply(404, {"error": "not found"})
            size = int(self.headers.get("Content-Length") or 0)
            if not 0 < size <= MAX_BODY:
                raise Rejected("request size out of bounds")
            answer, trace = decide(json.loads(self.rfile.read(size)))
            line.update(trace)
            self.reply(200, answer)
        except (Rejected, ValueError, TypeError) as e:
            line["error"] = str(e)[:160]
            self.reply(400, {"error": "request rejected"})
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            line["error"] = f"model unreachable: {type(e).__name__}"
            self.reply(502, {"error": "decision model unreachable"})
        finally:
            line["seconds"] = round(time.time() - start, 3)
            log(line)


if __name__ == "__main__":
    host, port = LISTEN.rsplit(":", 1)
    ThreadingHTTPServer((host, int(port)), Handler).serve_forever()
