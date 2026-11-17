#!/usr/bin/env python3
"""Each workspace runs under gVisor, makes Office files, builds code, has no internet, and is granted to one account.

Usage: python3 test.py   (as root: reads machine.env, versions.lock and the workspace secret)"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(ROOT, "tests"))
from owui import Report, env_file  # noqa: E402

CHECK = r"""
set -e
rm -rf ~/.doctor && mkdir ~/.doctor && cd ~/.doctor
python3 - <<'PY'
import openpyxl, docx, pptx, pypdf, pdfplumber, reportlab
wb = openpyxl.Workbook(); ws = wb.active
ws["A1"], ws["A2"], ws["A3"] = 2, 3, "=SUM(A1:A2)"; wb.save("book.xlsx")
d = docx.Document(); d.add_heading("Title", 1); d.save("doc.docx")
p = pptx.Presentation()
for n in range(10): p.slides.add_slide(p.slide_layouts[1]).shapes.title.text = f"Slide {n + 1}"
p.save("deck.pptx")
PY
echo "formula $(python3 -c "import openpyxl; print(openpyxl.load_workbook('book.xlsx').active['A3'].value)")"
soffice --headless --convert-to pdf book.xlsx >/dev/null 2>&1 && echo "office opens book.pdf"
git init -q proj && cd proj && printf 'def add(a, b):\n    return a - b\n' > calc.py
printf 'from calc import add\n\ndef test_add():\n    assert add(2, 3) == 5\n' > test_calc.py
python3 -m pytest -q >/dev/null 2>&1 || echo "failing test seen"
cd .. && cargo --version >/dev/null && node --version >/dev/null && gcc --version >/dev/null && echo "compilers ok"
curl -s -m 4 https://1.1.1.1 >/dev/null 2>&1 && echo "internet reached" || echo "internet blocked"
for h in stt tts ocr images; do getent hosts $h >/dev/null && echo "name $h found"; done
curl -s -m 3 -o /dev/null http://CORE_WEBUI:8080/health && echo "core reached" || echo "core blocked"
if [ -d ~/SHARED_NAME ]; then touch ~/SHARED_NAME/.doctor 2>/dev/null && echo "shared writable" || echo "shared read-only, $(ls ~/SHARED_NAME | wc -l) entries"; fi
"""


def sh(*args, stdin=None):
    return subprocess.run(args, capture_output=True, text=True, input=stdin).stdout.strip()


def main():
    m, lock = env_file("machine.env"), env_file("versions.lock")
    t = Report("modules / workspace")
    common = os.path.join(ROOT, "lib", "common.sh")
    os.environ["WORKSPACE_SECRET"] = sh("bash", "-c", f'. "{common}"; load_settings; secret WEBUI_SECRET_KEY')
    connections = os.path.join(HERE, "connections.py")
    people = m.get("ALICE_WORKSPACE_USERS", "").split() + ["workspace-tests"]
    for email in people:
        ident, key = sh("python3", "-I", connections, "id", email), sh("python3", "-I", connections, "key", email)
        container = f"{m['ALICE_PREFIX']}-workspace-{ident}"
        runtime = sh("docker", "container", "inspect", container, "-f", "{{.HostConfig.Runtime}}")
        t.check(runtime == "runsc", f"{container} runs under gVisor", runtime)
        probe = ("import json, sys, urllib.request\n"
                 "req = urllib.request.Request(f'http://{sys.argv[1]}:8000/execute?wait=240', sys.stdin.read().encode(),"
                 " {'Authorization': 'Bearer ' + sys.argv[2], 'Content-Type': 'application/json'})\n"
                 "r = json.load(urllib.request.urlopen(req, timeout=300))\n"
                 "print(''.join(o.get('data', '') for o in r.get('output', [])))")
        out = sh("docker", "run", "--rm", "-i", f"--network={m.get('ALICE_NET_WORKSPACE') or m['ALICE_PREFIX'] + '-workspace'}", "--entrypoint", "python3",
                 lock["PYTHON_IMAGE"], "-c", probe, container, key, stdin=json.dumps({"command": CHECK.replace("SHARED_NAME", m.get("ALICE_SHARED_NAME") or "shared")
                                           .replace("CORE_WEBUI", m["ALICE_NET_CORE_SUBNET"].rsplit(".", 1)[0] + ".2")}))
        t.check("formula =SUM(A1:A2)" in out, "an Excel formula stays live")
        t.check("office opens book.pdf" in out, "LibreOffice opens the workbook")
        t.check("failing test seen" in out, "a project's failing test is run and seen")
        t.check("compilers ok" in out, "Rust, Node and C are there")
        t.check("internet blocked" in out, "the workspace cannot reach the internet", "" if "internet blocked" in out else out[-200:])
        t.check("core blocked" in out, "the workspace cannot reach the core network (n8n, Home Assistant, decision…)")
        for h in [x for x in ("stt", "tts", "ocr", "images") if x in m.get("ALICE_MODULES", "").split()]:
            t.check(f"name {h} found" in out, f"a workspace finds the {h} service by name")
        if m.get("ALICE_SHARED_PATH"):
            t.check("shared read-only" in out, "the shared folder is readable and cannot be written", out.splitlines()[-1:])
    env = os.path.join(m["ALICE_DATA_DIR"], "workspace", "openwebui.conf")
    line = open(env, encoding="utf-8").read() if os.path.exists(env) else "TERMINAL_SERVER_CONNECTIONS=[]"
    granted = json.loads(line.split("=", 1)[1])
    t.check(len(granted) == len(people), "every person's workspace is connected in Open WebUI",
            f"{len(granted)} of {len(people)} (accounts are created first, then: Update one module → workspace)")
    t.check(all(len(c["config"]["access_grants"]) == 1 and c["config"]["access_grants"][0]["principal_id"] not in ("*", "")
                for c in granted), "each workspace is granted to its own account only")
    t.done()


if __name__ == "__main__":
    main()
