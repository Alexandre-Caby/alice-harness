#!/usr/bin/env python3
"""API-level checks: closed endpoints, account isolation, effective settings, approval patch in the container.

Usage: ALICE_TEST_URL=... ALICE_TEST_ADMIN_EMAIL=... ALICE_TEST_ADMIN_PASSWORD=... python3 test.py [container name]"""
import os
import subprocess
import sys
import uuid

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tests"))
from owui import ApiError, Client, Report, TempUser, settings  # noqa: E402

DENIED = (401, 403, 404)


def main():
    url, email, password = settings()
    container = sys.argv[1] if len(sys.argv) > 1 else "alice-openwebui"
    t = Report("core / open-webui")
    anonymous = Client(url)

    t.check(anonymous.status("/health") == 200, "the server answers")
    try:
        intruder = anonymous.call("/api/v1/auths/signup", {"name": "x", "email": f"x-{uuid.uuid4().hex[:6]}@alice-harness.test",
                                                           "password": uuid.uuid4().hex})
        code = 200
    except ApiError as e:
        intruder, code = None, e.code
    t.check(code in (400, 401, 403), "self sign-up is closed", f"HTTP {code}")
    t.check(anonymous.status("/api/v1/chats/") in DENIED, "no data without an account")

    admin = Client.signin(url, email, password)
    if intruder and intruder.get("id"):
        admin.status(f"/api/v1/users/{intruder['id']}", method="DELETE")
    config = admin.call("/api/config")
    features = config.get("features", {})
    t.check(features.get("enable_signup") is False, "sign-up disabled in the running settings")
    t.check(features.get("enable_channels") is not True, "channels disabled (they would force full tool access)")
    t.check(features.get("enable_web_search") is True, "web search enabled")
    t.check(features.get("enable_tool_permissions_auto") is True, "approval gate in auto mode")

    a, b = TempUser(admin, "a"), TempUser(admin, "b")
    try:
        t.check(b.client.status("/api/v1/users/") in DENIED, "an ordinary account cannot list accounts")

        marker = f"locker code {uuid.uuid4().hex[:6]}"
        a.client.call("/api/v1/memories/add", {"content": marker})
        mine = [m["content"] for m in a.client.call("/api/v1/memories/") or []]
        theirs = [m["content"] for m in b.client.call("/api/v1/memories/") or []]
        t.check(marker in mine and marker not in theirs, "memories are private to each account")

        chat_id = a.client.call("/api/v1/chats/new", {"chat": {"title": "private", "models": [], "messages": []}})["id"]
        t.check(b.client.status(f"/api/v1/chats/{chat_id}") in DENIED, "a chat cannot be opened by another account")

        boundary = uuid.uuid4().hex
        body = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"note.txt\"\r\n"
                f"Content-Type: text/plain\r\n\r\nprivate note\r\n--{boundary}--\r\n").encode()
        file_id = a.client.call("/api/v1/files/?process=false", body,
                                headers={"Content-Type": f"multipart/form-data; boundary={boundary}"})["id"]
        t.check(b.client.status(f"/api/v1/files/{file_id}") in DENIED, "a file cannot be read by another account")

        private = a.client.call("/api/v1/knowledge/create", {"name": "private library", "description": "test"})
        shared = admin.call("/api/v1/knowledge/create", {"name": "shared library", "description": "test",
                               "access_grants": [{"principal_type": "user", "principal_id": "*", "permission": "read"}]})
        t.check(b.client.status(f"/api/v1/knowledge/{private['id']}") in DENIED, "a private library stays private")
        t.check(b.client.status(f"/api/v1/knowledge/{shared['id']}") == 200, "a library the administrator shares is readable by all")
        a.client.status(f"/api/v1/knowledge/{private['id']}/delete", method="DELETE")
        admin.status(f"/api/v1/knowledge/{shared['id']}/delete", method="DELETE")
    except ApiError as e:
        t.check(False, "account separation checks ran to the end", str(e))
    finally:
        a.delete(); b.delete()

    r = subprocess.run(["docker", "exec", container, "grep", "-c", 'there is no "full access" mode',
                        "/app/backend/open_webui/utils/tool_permissions.py"], capture_output=True, text=True)
    t.check(r.stdout.strip() == "1", "the approval patch is active in the running container", r.stderr.strip()[:80])
    t.done()


if __name__ == "__main__":
    main()
