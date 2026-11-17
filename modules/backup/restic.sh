#!/usr/bin/env bash
# Runs restic on the backup repository: restic.sh <restic arguments>. Extra read-only paths in RESTIC_MOUNTS.
set -euo pipefail
. "$(dirname "$0")/../../lib/common.sh"
load_settings

repo=${ALICE_BACKUP_DIR:-/var/backups/$ALICE_PREFIX}
key=/etc/alice-harness/$ALICE_PREFIX-backup.key
mounts=()
for p in ${RESTIC_MOUNTS:-}; do mounts+=(-v "$p:$p:ro"); done
# No network; reading other users' files needs DAC_READ_SEARCH, nothing more.
exec docker run --rm -i --network none --cap-drop ALL --cap-add DAC_READ_SEARCH --security-opt no-new-privileges:true \
  -e RESTIC_REPOSITORY=/repo -e RESTIC_PASSWORD_FILE=/key -e RESTIC_CACHE_DIR=/repo/.cache \
  -v "$repo:/repo" -v "$key:/key:ro" "${mounts[@]}" "$RESTIC_IMAGE" "$@"
