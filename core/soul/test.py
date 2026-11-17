#!/usr/bin/env python3
"""Usage: ALICE_TEST_URL=... ALICE_TEST_ADMIN_EMAIL=... ALICE_TEST_ADMIN_PASSWORD=... python3 test.py"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tests"))
from owui import ApiError, Client, Report, TempUser, settings  # noqa: E402

spec = importlib.util.spec_from_file_location("presets", os.path.join(HERE, "presets.py"))
presets = importlib.util.module_from_spec(spec); spec.loader.exec_module(presets)


def main():
    t = Report("core / soul")
    m = presets.env_file("machine.env")
    expected = presets.render(m.get("ALICE_SOUL_FILE", ""))
    url, email, password = settings()
    admin = Client.signin(url, email, password)
    user = TempUser(admin, "soul")
    try:
        visible = {x["id"] for x in user.client.call("/api/models")["data"]}
        for ident, base, _, think in presets.presets(m["ALICE_PRESETS"]):
            model = admin.call(f"/api/v1/models/model?id={ident}")
            system = (model.get("params") or {}).get("system", "")
            t.check(system == expected, f"preset '{ident}' carries the current soul")
            t.check(model.get("base_model_id") == base, f"preset '{ident}' runs on {base}")
            t.check((model.get("params") or {}).get("think", True) == think,
                    f"preset '{ident}' {'thinks' if think else 'answers without thinking first'}")
            t.check(ident in visible, f"preset '{ident}' is offered to an ordinary account")
            try:
                r = user.client.call("/api/chat/completions", {"model": ident, "stream": False, "messages": [
                    {"role": "user", "content": "Reply with the single word OK."}]})
                reply = r["choices"][0]["message"]["content"] or ""
                answered, detail = bool(reply.strip()), f"reply {reply[:80]!r}"
            except (ApiError, KeyError, IndexError) as e:
                answered, detail = False, str(e)
            t.check(answered, f"an ordinary account can chat with preset '{ident}'", detail)
    finally:
        user.delete()
    t.done()


if __name__ == "__main__":
    main()
