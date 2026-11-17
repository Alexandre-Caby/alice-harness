#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/../../lib/common.sh"
load_settings

net=${ALICE_NET_CORE_SUBNET%.0/24}
m=/models
gpu_args
docker rm -f "$(name images)" >/dev/null 2>&1 || true
docker run -d --name "$(name images)" --restart unless-stopped \
  --network "$ALICE_NET_CORE" --ip "$net.60" --network-alias images \
  --cap-drop ALL --security-opt no-new-privileges:true --read-only --tmpfs /tmp --memory 24g --pids-limit 256 "${GPU[@]}" \
  -v "$ALICE_DATA_DIR/images/models:/models:ro" "$(name images):local" \
  --diffusion-model "$m/$(basename "$IMAGES_DIFFUSION_URL")" --llm "$m/$(basename "$IMAGES_TEXT_ENCODER_URL")" \
  --vae "$m/$(basename "$IMAGES_VAE_URL")" --vae-tiling --steps 4 --seed -1 --cfg-scale 1.0 --sampling-method euler \
  --listen-ip 0.0.0.0 --listen-port 7860 >/dev/null

join_workspaces "$(name images)" 60
wait_up "images module" 240 curl -sf -m 2 "http://$net.60:7860/v1/models"
