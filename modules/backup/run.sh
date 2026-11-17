#!/usr/bin/env bash
# Creates the key and the repository once, installs the nightly timer and starts a first backup in the background.
set -euo pipefail
. "$(dirname "$0")/../../lib/common.sh"
load_settings

here=$ALICE_ROOT/modules/backup
repo=${ALICE_BACKUP_DIR:-/var/backups/$ALICE_PREFIX}
key=/etc/alice-harness/$ALICE_PREFIX-backup.key
install -d -m 700 "$repo" "$ALICE_DATA_DIR/backup"
install -d -m 755 /etc/alice-harness
if [ ! -s "$key" ]; then
  (umask 077 && openssl rand -base64 32 > "$key")
  info "backup key created: $key — keep a copy off this machine, the backup cannot be read without it"
fi
chmod 600 "$key"
bash "$here/restic.sh" cat config >/dev/null 2>&1 || bash "$here/restic.sh" init >/dev/null

unit=/etc/systemd/system/$ALICE_PREFIX-backup
cat > "$unit.service" <<EOF
[Unit]
Description=Alice Harness ($ALICE_PREFIX): nightly backup
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
Nice=10
IOSchedulingClass=idle
ExecStart=/bin/bash $here/backup.sh
EOF
cat > "$unit.timer" <<EOF
[Unit]
Description=Alice Harness ($ALICE_PREFIX): nightly backup

[Timer]
OnCalendar=*-*-* 03:30
RandomizedDelaySec=15m
Persistent=true

[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now "$ALICE_PREFIX-backup.timer" >/dev/null 2>&1
# The first backup runs now, in the background; later ones at night.
bash "$here/restic.sh" snapshots --latest 1 --json 2>/dev/null | grep '"time"' >/dev/null ||
  systemctl start --no-block "$ALICE_PREFIX-backup.service"
info "backup module ready: $repo, every night"
