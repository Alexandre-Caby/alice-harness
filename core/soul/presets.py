#!/usr/bin/env python3
"""Render the soul and attach it to every preset in ALICE_PRESETS.

The image rule comes from the images module: the prompt language depends on the image model.

Usage: ALICE_TEST_URL=... ALICE_TEST_ADMIN_EMAIL=... ALICE_TEST_ADMIN_PASSWORD=... python3 presets.py"""
import os
import re
import sys
import urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(ROOT, "tests"))
from owui import ApiError, Client, env_file, settings  # noqa: E402


def render(path=""):
    """Relative paths are from the repo root."""
    soul = open(os.path.join(ROOT, path) if path else os.path.join(HERE, "SOUL.md"), encoding="utf-8").read()
    rule_file = os.path.join(ROOT, "modules", "images", "soul.txt")
    images = "images" in os.environ.get("ALICE_MODULES", "").split()
    rule = open(rule_file, encoding="utf-8").read().strip() if images and os.path.exists(rule_file) else ""
    soul = soul.replace("  {{IMAGE_PROMPT_RULE}}\n", f"  {rule}\n" if rule else "")
    left = re.findall(r"\{\{[A-Z_]+\}\}", soul)
    if left:
        raise SystemExit(f"unresolved placeholders in the soul: {left}")
    return soul.strip()


def presets(spec):
    """'id=model|Name' or 'id=model|Name|think=off', separated by ';' -> [(id, model, name, think)]."""
    out = []
    for item in filter(None, (s.strip() for s in spec.split(";"))):
        ident, rest = item.split("=", 1)
        base, _, rest = rest.partition("|")
        label, _, option = rest.partition("|")
        out.append((ident.strip(), base.strip(), label.strip() or ident.strip(), option.strip() != "think=off"))
    return out


def main():
    m = env_file("machine.env")
    soul = render(m.get("ALICE_SOUL_FILE", ""))
    url, email, password = settings()
    admin = Client.signin(url, email, password)
    everyone = [{"principal_type": "user", "principal_id": "*", "permission": "read"}]
    for ident, base, label, think in presets(m["ALICE_PRESETS"]):
        # A user can only use a preset whose base model they can read: share the base models, hidden.
        try:
            admin.call(f"/api/v1/models/model?id={urllib.parse.quote(base, safe='')}")
        except ApiError:
            admin.call("/api/v1/models/create", {"id": base, "base_model_id": None, "name": base, "is_active": True,
                                                 "meta": {"hidden": True}, "params": {}, "access_grants": everyone})
            print(f"  shared   {base} (hidden)")
        body = {"id": ident, "base_model_id": base, "name": label, "is_active": True,
                "meta": {"capabilities": {"file_upload": True, "web_search": True,
                                                           "image_generation": "images" in os.environ.get("ALICE_MODULES", "").split(),
                                                           "citations": True, "status_updates": True, "builtin_tools": True}},
                "params": {"system": soul, "function_calling": "native", **({} if think else {"think": False})},
                "access_grants": everyone}
        try:
            admin.call(f"/api/v1/models/model?id={urllib.parse.quote(ident, safe='')}")
            admin.call("/api/v1/models/model/update", body)
            print(f"  updated  {ident} ({base})")
        except ApiError:
            admin.call("/api/v1/models/create", body)
            print(f"  created  {ident} ({base})")


if __name__ == "__main__":
    main()
