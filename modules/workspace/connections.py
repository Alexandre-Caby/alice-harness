#!/usr/bin/env python3
"""Workspace names, keys, and the Open WebUI setting that connects them.

The TESTS workspace belongs to the group of the same name; tests join it with temporary accounts and never touch a
person's workspace.

Usage: connections.py id EMAIL | key EMAIL | env EMAIL...
  key and env read WORKSPACE_SECRET; env signs in as the admin (ALICE_TEST_*) and prints TERMINAL_SERVER_CONNECTIONS."""
import hashlib
import hmac
import json
import os
import sys
import urllib.parse

TESTS = "workspace-tests"

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tests"))
from owui import ApiError, Client, settings  # noqa: E402


def ident(email):
    return hashlib.sha256(email.lower().encode()).hexdigest()[:10]


def key(email):
    return hmac.new(os.environ["WORKSPACE_SECRET"].encode(), f"workspace:{email.lower()}".encode(),
                    hashlib.sha256).hexdigest()


def env(emails):
    prefix = os.environ["ALICE_PREFIX"]
    try:
        admin = Client.signin(*settings())
    except (ApiError, OSError) as e:
        print(f"workspace: Open WebUI not reachable ({e}); terminals not connected yet", file=sys.stderr)
        emails = []
    connections = []
    template = os.environ.get("ALICE_WORKSPACE_LABEL") or "Workspace of {name}"
    for email in emails:
        if email == TESTS:
            group = next((g for g in admin.call("/api/v1/groups/") if g["name"] == TESTS), None) or admin.call(
                "/api/v1/groups/create", {"name": TESTS, "description": "Temporary test accounts"})
            grant, label = {"principal_type": "group", "principal_id": group["id"], "permission": "read"}, "tests"
        else:
            found = admin.call(f"/api/v1/users/?query={urllib.parse.quote(email)}")["users"]
            user = next((u for u in found if u["email"].lower() == email.lower()), None)
            if not user:
                print(f"workspace: no account for {email} yet; its terminal is not connected", file=sys.stderr)
                continue
            grant, label = {"principal_type": "user", "principal_id": user["id"], "permission": "read"}, user["name"]
        connections.append({
            "id": f"workspace-{ident(email)}", "name": template.replace("{name}", label), "enabled": True,
            "url": f"http://{prefix}-workspace-{ident(email)}:8000", "path": "/openapi.json",
            "auth_type": "bearer", "key": key(email),
            # Chat attachments land in the workspace, where the model can edit them.
            "config": {"chat_uploads": "filesystem",
                       "access_grants": [grant]},
        })
    print("TERMINAL_SERVER_CONNECTIONS=" + json.dumps(connections))


if __name__ == "__main__":
    action, args = sys.argv[1], sys.argv[2:]
    if action == "env":
        env(args)
    else:
        print({"id": ident, "key": key}[action](args[0]))
