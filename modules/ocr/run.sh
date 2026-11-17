#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/../../lib/common.sh"
load_settings

state=$ALICE_DATA_DIR/ocr
net=${ALICE_NET_CORE_SUBNET%.0/24}
mkdir -p "$state"
sed "s/{{LANGUAGES}}/${ALICE_OCR_LANGUAGES:-eng}/" "$ALICE_ROOT/modules/ocr/tika-config.json" > "$state/tika-config.json"

docker rm -f "$(name ocr)" >/dev/null 2>&1 || true
docker run -d --name "$(name ocr)" --restart unless-stopped \
  --network "$ALICE_NET_CORE" --ip "$net.30" --network-alias ocr \
  --cap-drop ALL --security-opt no-new-privileges:true --memory 2g --pids-limit 256 \
  -v "$state/tika-config.json:/tika-config.json:ro" "$TIKA_IMAGE" -c /tika-config.json >/dev/null

join_workspaces "$(name ocr)" 30
wait_up "ocr module" 60 answers "http://$net.30:9998/tika" 200
