#!/usr/bin/env bash
# On both networks: n8n's only way out.
set -euo pipefail
. "$(dirname "$0")/../../lib/common.sh"
load_settings

state=$ALICE_DATA_DIR/egress
net=${ALICE_NET_CORE_SUBNET%.0/24}
install -d -m 755 "$state"
sed "s#{{INTERNAL}}#$ALICE_NET_CORE_SUBNET $ALICE_NET_EGRESS_SUBNET#" "$ALICE_ROOT/security/egress/squid.conf" > "$state/squid.conf"
tr -s ' ' '\n' <<< "${ALICE_EGRESS_N8N:-}" > "$state/n8n.txt"

docker rm -f "$(name egress)" >/dev/null 2>&1 || true
docker run -d --name "$(name egress)" --restart unless-stopped \
  --network "$ALICE_NET_CORE" --ip "$net.5" --network-alias proxy \
  --cap-drop ALL --security-opt no-new-privileges:true --read-only --tmpfs /tmp --tmpfs /run --memory 256m --pids-limit 128 \
  -v "$state/squid.conf:/etc/squid/squid.conf:ro" -v "$state/n8n.txt:/etc/squid/n8n.txt:ro" "$(name egress):local" >/dev/null
docker network connect "$ALICE_NET_EGRESS" "$(name egress)"

wait_up "egress proxy" 30 answers "http://$net.5:3128/"
