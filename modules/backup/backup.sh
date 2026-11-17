#!/usr/bin/env bash
# Nightly backup (run by the backup timer): the data folder without the models, machine.env, /etc/alice-harness and
# ALICE_BACKUP_EXTRA. SQLite databases are copied with the SQLite backup API first: a file copied while it is written
# can be unreadable.
set -euo pipefail
here=$(dirname "$(readlink -f "$0")")
. "$here/../../lib/common.sh"
load_settings

repo=${ALICE_BACKUP_DIR:-/var/backups/$ALICE_PREFIX}
copies=$ALICE_DATA_DIR/backup/sqlite
excludes=$ALICE_DATA_DIR/backup/excludes
rm -rf "$copies"
install -d -m 700 "$copies"

{
  echo "$repo"
  echo "$ALICE_DATA_DIR/*/models"
  echo "$ALICE_DATA_DIR/tts/model"
} > "$excludes"
find "$ALICE_DATA_DIR" -path "$ALICE_DATA_DIR/backup" -prune -o -path "$ALICE_DATA_DIR/*/models" -prune \
  -o -type f \( -name '*.db' -o -name '*.sqlite' -o -name '*.sqlite3' \) -print0 |
  python3 -I -B -c '
import os, sqlite3, sys
copies, excludes = sys.argv[1], sys.argv[2]
with open(excludes, "a") as out:
    for path in sys.stdin.read().split("\0"):
        if not path:
            continue
        with open(path, "rb") as f:
            if f.read(16) != b"SQLite format 3\x00":
                continue
        target = copies + path
        os.makedirs(os.path.dirname(target), mode=0o700, exist_ok=True)
        src = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
        dst = sqlite3.connect(target)
        src.backup(dst)
        dst.close()
        src.close()
        for suffix in ("", "-wal", "-shm", "-journal"):
            out.write(path + suffix + "\n")
' "$copies" "$excludes"

paths=("$ALICE_DATA_DIR" "$ALICE_ROOT/machine.env")
[ -d /etc/alice-harness ] && paths+=(/etc/alice-harness)
for p in ${ALICE_BACKUP_EXTRA:-}; do
  if [ -e "$p" ]; then paths+=("$p"); else echo "backup: $p does not exist, skipped" >&2; fi
done

run() { RESTIC_MOUNTS="${paths[*]}" bash "$here/restic.sh" "$@"; }
run unlock >/dev/null 2>&1 || true
# The excludes file is inside the data folder, which is mounted.
run backup --host "$ALICE_PREFIX" --tag nightly --exclude-file "$excludes" --one-file-system "${paths[@]}"
run forget --host "$ALICE_PREFIX" --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
rm -rf "$copies"
