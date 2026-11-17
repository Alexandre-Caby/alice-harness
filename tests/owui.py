"""Open WebUI API client and settings reader for the tests and the deploy scripts."""
import json
import os
import secrets
import time
import urllib.error
import urllib.request
import uuid


class ApiError(Exception):
    def __init__(self, code, body):
        super().__init__(f"HTTP {code}: {body[:200]}")
        self.code = code


def env_file(name):
    """The values of machine.env or versions.lock."""
    values = {}
    for line in open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", name), encoding="utf-8"):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            values[k] = v.strip().strip('"')
    return values


def settings():
    try:
        return os.environ["ALICE_TEST_URL"].rstrip("/"), os.environ["ALICE_TEST_ADMIN_EMAIL"], os.environ["ALICE_TEST_ADMIN_PASSWORD"]
    except KeyError as missing:
        raise SystemExit(f"missing environment variable {missing}: set ALICE_TEST_URL, ALICE_TEST_ADMIN_EMAIL, ALICE_TEST_ADMIN_PASSWORD")


class Client:
    def __init__(self, url, token=None):
        self.url, self.token = url, token

    def call(self, path, body=None, method=None, raw=False, timeout=120, headers=None):
        h = {"Content-Type": "application/json"} if body is not None and not isinstance(body, bytes) else {}
        if self.token:
            h["Authorization"] = f"Bearer {self.token}"
        h.update(headers or {})
        data = body if isinstance(body, bytes) or body is None else json.dumps(body).encode()
        req = urllib.request.Request(self.url + path, data=data, headers=h, method=method)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                payload = r.read()
        except urllib.error.HTTPError as e:
            raise ApiError(e.code, e.read().decode(errors="replace")) from None
        return payload if raw else json.loads(payload or b"null")

    def status(self, path, body=None, method=None):
        try:
            self.call(path, body, method)
            return 200
        except ApiError as e:
            return e.code

    @classmethod
    def signin(cls, url, email, password):
        c = cls(url)
        c.token = c.call("/api/v1/auths/signin", {"email": email, "password": password})["token"]
        return c


class TempUser:

    def __init__(self, admin, label):
        self.admin = admin
        self.email = f"test-{label}-{uuid.uuid4().hex[:8]}@alice-harness.test"
        self.password = secrets.token_urlsafe(18)
        self.id = admin.call("/api/v1/auths/add", {"name": f"Test {label}", "email": self.email,
                                                   "password": self.password, "role": "user"})["id"]
        self.client = Client.signin(admin.url, self.email, self.password)

    def test_workspace(self):
        """Join the test workspace group; returns its terminal id, or None if the module is off."""
        group = next((g for g in self.admin.call("/api/v1/groups/") if g["name"] == "workspace-tests"), None)
        if not group:
            return None
        self.admin.call(f"/api/v1/groups/id/{group['id']}/users/add", {"user_ids": [self.id]})
        return next((t["id"] for t in self.client.call("/api/v1/terminals/")), None)

    def delete(self):
        # Deleting an account only removes its chats; remove the rest first, as the user, so shared items survive.
        c = self.client
        cleanup = [("/api/v1/memories/delete/user", "DELETE")]
        for path, items, delete in (
                ("/api/v1/files/?content=false", lambda r: r["items"], "/api/v1/files/{}"),
                ("/api/v1/knowledge/", lambda r: r["items"], "/api/v1/knowledge/{}/delete"),
                ("/api/v1/notes/", lambda r: r, "/api/v1/notes/{}/delete"),
                ("/api/v1/automations/list", lambda r: r["items"], "/api/v1/automations/{}/delete")):
            try:
                owned = [i["id"] for i in items(c.call(path)) if i.get("user_id") == self.id]
            except (ApiError, KeyError, TypeError):
                owned = []
            cleanup += [(delete.format(i), "DELETE") for i in owned]
        for path, method in cleanup:
            c.status(path, method=method)
        try:
            self.admin.call(f"/api/v1/users/{self.id}", method="DELETE")
        except ApiError:
            pass


def chat(client, model, text, params=None, features=None, tool_ids=None, terminal_id=None, timeout=900):
    """Returns once the reply is done, failed, or waits for an approval."""
    chat_id = client.call("/api/v1/chats/new", {"chat": {"title": "test", "models": [model], "messages": []}})["id"]
    message_id = str(uuid.uuid4())
    body = {"model": model, "stream": True, "chat_id": chat_id, "id": message_id,
            "session_id": "test-" + uuid.uuid4().hex[:8], "messages": [{"role": "user", "content": text}]}
    if params:
        body["params"] = params
    if features:
        body["features"] = features
    if tool_ids:
        body["tool_ids"] = tool_ids
    if terminal_id:
        body["terminal_id"] = terminal_id
    client.call("/api/chat/completions", body, raw=True, timeout=timeout)
    start = time.monotonic()
    while time.monotonic() - start < timeout:
        m = client.call(f"/api/v1/chats/{chat_id}")["chat"].get("history", {}).get("messages", {}).get(message_id, {})
        calls = [o for o in m.get("output") or [] if o.get("type") == "function_call"]
        pending = [o.get("name") for o in calls if o.get("status") == "pending"]
        if pending or m.get("error") or m.get("done"):
            return {"chat_id": chat_id, "message": m, "pending": pending,
                    "done_calls": [o.get("name") for o in calls if o.get("status") == "completed"],
                    "error": m.get("error"), "seconds": time.monotonic() - start}
        time.sleep(2)
    return {"chat_id": chat_id, "message": {}, "pending": [], "done_calls": [], "error": "timeout",
            "seconds": time.monotonic() - start}


class Report:

    def __init__(self, title):
        self.title, self.failed = title, 0
        print(f"== {title}")

    def check(self, ok, what, detail=""):
        print(f"  {'PASS' if ok else 'FAIL'}  {what}" + (f" ({detail})" if detail else ""))
        self.failed += 0 if ok else 1
        return ok

    def done(self):
        print(f"{self.title}: {'all checks passed' if not self.failed else f'{self.failed} check(s) failed'}")
        raise SystemExit(1 if self.failed else 0)
