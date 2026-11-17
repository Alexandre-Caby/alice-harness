#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/../../lib/common.sh"
load_settings

state=$ALICE_DATA_DIR/stt
net=${ALICE_NET_CORE_SUBNET%.0/24}
mkdir -p "$state/terms"
touch "$state/terms/terms.txt"
gpu_args
docker rm -f "$(name stt-model)" "$(name stt)" >/dev/null 2>&1 || true
docker run -d --name "$(name stt-model)" --restart unless-stopped \
  --network "$ALICE_NET_CORE" --ip "$net.51" --network-alias stt-model \
  --cap-drop ALL --security-opt no-new-privileges:true --read-only --tmpfs /tmp:size=1g --pids-limit 2048 "${GPU[@]}" \
  -v "$state/models:/models:ro" "$(name stt-model):local" \
  serve --asr-model "/models/$(basename "$STT_MODEL_URL")" --host 0.0.0.0 --port 8080 >/dev/null
docker run -d --name "$(name stt)" --restart unless-stopped \
  --network "$ALICE_NET_CORE" --ip "$net.50" --network-alias stt \
  --cap-drop ALL --security-opt no-new-privileges:true --read-only --tmpfs /tmp --memory 1g --pids-limit 64 \
  -e UPSTREAM=http://stt-model:8080 -e LANGUAGE="${ALICE_STT_LANGUAGE:-English}" -e TERMS=/terms/terms.txt \
  -v "$state/terms:/terms:ro" "$(name stt):local" >/dev/null

join_workspaces "$(name stt)" 50
wait_up "stt model" 360 answers "http://$net.51:8080/"
wait_up "stt module" 60 answers "http://$net.50:7864/health" 200
