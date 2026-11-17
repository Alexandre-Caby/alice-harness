#!/usr/bin/env bash
# On the egress network to reach devices. Its MCP server is connected in Open WebUI and only sees the entities
# exposed to voice assistants.
set -euo pipefail
. "$(dirname "$0")/../../lib/common.sh"
load_settings

state=$ALICE_DATA_DIR/home-assistant
net=${ALICE_NET_CORE_SUBNET%.0/24}
install -d -m 700 "$state" "$state/config"
# Home Assistant keeps its HTTP settings (trusted proxies) in its own interface, not in this file.
[ -f "$state/config/configuration.yaml" ] || echo "default_config:" > "$state/config/configuration.yaml"

docker rm -f "$(name home-assistant)" >/dev/null 2>&1 || true
docker run -d --name "$(name home-assistant)" --restart unless-stopped \
  --network "$ALICE_NET_CORE" --ip "$net.90" --network-alias home-assistant \
  --cap-drop ALL --security-opt no-new-privileges:true --memory 2g --pids-limit 512 \
  -e TZ="$ALICE_TIMEZONE" -v "$state/config:/config" "$HOME_ASSISTANT_IMAGE" >/dev/null
docker network connect "$ALICE_NET_EGRESS" "$(name home-assistant)"
wait_up "home-assistant module (http://$net.90:8123)" 180 answers "http://$net.90:8123/api/" 401
