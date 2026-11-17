#!/usr/bin/env bash
# One Open Terminal per ALICE_WORKSPACE_USERS account, under gVisor, on the workspace network, plus one for the tests.
# Rerun after adding accounts: each grant needs the account id.
set -euo pipefail
. "$(dirname "$0")/../../lib/common.sh"
load_settings

state=$ALICE_DATA_DIR/workspace
install -d -m 711 "$state"
WORKSPACE_SECRET=$(secret WEBUI_SECRET_KEY)
export WORKSPACE_SECRET

# Shared folder, read-only, at ~/<ALICE_SHARED_NAME>
shared=()
if [ -n "${ALICE_SHARED_PATH:-}" ]; then
  findmnt -n -o OPTIONS --target "$ALICE_SHARED_PATH" | tr ',' '\n' | grep -x ro >/dev/null || die "$ALICE_SHARED_PATH is not mounted read-only"
  shared_name=${ALICE_SHARED_NAME:-shared}
  [[ $shared_name =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "ALICE_SHARED_NAME must be a plain folder name"
  shared=(-v "$ALICE_SHARED_PATH:/home/user/$shared_name:ro")
fi

# Only Open WebUI and these services share the workspaces' network. gVisor ignores Docker's internal DNS: name them
# (the numbers each module joins with).
net=${ALICE_NET_WORKSPACE_SUBNET%.0/24}
hosts=()
for s in stt:50 tts:40 ocr:30 images:60; do
  has "${s%%:*}" && hosts+=(--add-host "${s%%:*}:$net.${s#*:}")
done

read -ra people <<< "${ALICE_WORKSPACE_USERS:-}"
people+=(workspace-tests)
for c in $(docker ps -a --filter label=alice-harness.workspace --filter name="^$(name workspace-)" --format '{{.Names}}'); do
  docker rm -f "$c" >/dev/null
done
for email in "${people[@]}"; do
  id=$(python3 -I -B "$ALICE_ROOT/modules/workspace/connections.py" id "$email")
  install -d -m 700 -o 1000 -g 1000 "$state/$id"
  OPEN_TERMINAL_API_KEY=$(python3 -I -B "$ALICE_ROOT/modules/workspace/connections.py" key "$email") \
  docker run -d --name "$(name "workspace-$id")" --restart unless-stopped --runtime runsc \
    --label alice-harness.workspace="$id" --network "$ALICE_NET_WORKSPACE" \
    --cap-drop ALL --security-opt no-new-privileges:true --memory 4g --pids-limit 512 \
    --read-only --tmpfs /tmp:rw,exec \
    -e OPEN_TERMINAL_API_KEY -v "$state/$id:/home/user" "${shared[@]}" "${hosts[@]}" "$(name workspace):local" >/dev/null
  info "workspace $id up"
done

ALICE_TEST_URL="http://${ALICE_NET_CORE_SUBNET%.0/24}.2:8080" ALICE_TEST_ADMIN_EMAIL="$(secret WEBUI_ADMIN_EMAIL)" \
  ALICE_TEST_ADMIN_PASSWORD="$(secret WEBUI_ADMIN_PASSWORD)" \
  python3 -I -B "$ALICE_ROOT/modules/workspace/connections.py" env "${people[@]}" > "$state/openwebui.conf.new"
chmod 600 "$state/openwebui.conf.new"
mv "$state/openwebui.conf.new" "$state/openwebui.conf"
