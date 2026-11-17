#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/../../lib/common.sh"
load_settings

here=$ALICE_ROOT/modules/decision
state=$ALICE_DATA_DIR/decision
net=${ALICE_NET_CORE_SUBNET%.0/24}
model=$(basename "$DECISION_MODEL_URL")
mkdir -p "$state/log"
chown 65534:65534 "$state/log"
# Mounted from a root-owned copy so editing the repo can't widen the gate.
install -d -m 755 -o root -g root "$state/app"
install -m 444 -o root -g root "$here/adapter.py" "$here/allowlist.txt" "$state/app/"

gpu_args
docker rm -f "$(name decision-model)" "$(name decision-adapter)" >/dev/null 2>&1 || true

info "decision model"
# Kept loaded: a cold start misses Open WebUI's timeout.
docker run -d --name "$(name decision-model)" --restart unless-stopped \
  --network "$ALICE_NET_CORE" --ip "$net.11" --network-alias decision-model \
  --cap-drop ALL --security-opt no-new-privileges:true "${GPU[@]}" \
  -v "$state/models:/models:ro" "$LLAMACPP_SERVER_IMAGE" \
  -m "/models/$model" -ngl 99 -c 8192 -b 8192 -ub 8192 --host 0.0.0.0 --port 8080 >/dev/null

info "decision adapter"
docker run -d --name "$(name decision-adapter)" --restart unless-stopped \
  --network "$ALICE_NET_CORE" --ip "$net.10" --network-alias decision-adapter \
  --cap-drop ALL --security-opt no-new-privileges:true --read-only --memory 256m --pids-limit 64 \
  --user 65534:65534 \
  -e UPSTREAM=http://decision-model:8080 -e ALLOWLIST=/app/allowlist.txt -e LOG=/state/decisions.jsonl \
  -v "$state/app/adapter.py:/app/adapter.py:ro" -v "$state/app/allowlist.txt:/app/allowlist.txt:ro" -v "$state/log:/state" \
  "$PYTHON_IMAGE" python3 -I -B /app/adapter.py >/dev/null

wait_up "decision model" 360 answers "http://$net.11:8080/health" 200
wait_up "decision module" 60 answers "http://$net.10:8096/health" 200
