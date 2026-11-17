#!/usr/bin/env python3
"""The nightly timer is on, the key is root-only, the repository opens, and the last backup is less than two days old
(a repository created less than a day ago may still be waiting for its first one).

Usage: python3 test.py"""
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(ROOT, "tests"))
from owui import Report, env_file  # noqa: E402


m = env_file("machine.env")
prefix = m["ALICE_PREFIX"]
repo = m.get("ALICE_BACKUP_DIR") or f"/var/backups/{prefix}"
key = f"/etc/alice-harness/{prefix}-backup.key"
t = Report("backup")

timer = subprocess.run(["systemctl", "is-enabled", f"{prefix}-backup.timer"], capture_output=True, text=True).stdout.strip()
t.check(timer == "enabled", "the nightly backup timer is enabled", timer)
st = os.stat(key) if os.path.exists(key) else None
t.check(st is not None and st.st_uid == 0 and st.st_mode & 0o077 == 0, "the backup key exists and only root reads it")

# No lock: the nightly prune holds an exclusive one, which must not look like a failure.
out = subprocess.run(["bash", os.path.join(HERE, "restic.sh"), "--no-lock", "snapshots", "--host", prefix, "--json"],
                     capture_output=True, text=True)
t.check(out.returncode == 0, "the backup repository opens with its key", out.stderr[-200:])
snapshots = json.loads(out.stdout or "[]") if out.returncode == 0 else []
if snapshots:
    # restic writes nanoseconds; Python reads at most microseconds.
    last = max(datetime.fromisoformat(re.sub(r"(\.\d{6})\d+", r"\1", s["time"])) for s in snapshots)
    age = (datetime.now(timezone.utc) - last).total_seconds()
    t.check(age < 50 * 3600, "the last backup is less than two days old", f"{age / 3600:.0f} h, {len(snapshots)} kept")
else:
    young = time.time() - os.stat(os.path.join(repo, "config")).st_mtime < 24 * 3600 if os.path.exists(os.path.join(repo, "config")) else False
    t.check(young, "a first backup exists (or the repository is less than a day old)")
t.done()
