#!/usr/bin/env bash
# Outbound only through the egress proxy, limited to ALICE_EGRESS_N8N.
set -euo pipefail
. "$(dirname "$0")/../../lib/common.sh"
load_settings

state=$ALICE_DATA_DIR/n8n
net=${ALICE_NET_CORE_SUBNET%.0/24}
mkdir -p "$state"
chown 1000:1000 "$state"

N8N_ENCRYPTION_KEY=$(secret N8N_ENCRYPTION_KEY)
[ -n "$N8N_ENCRYPTION_KEY" ] || die "the secret N8N_ENCRYPTION_KEY is empty"
export N8N_ENCRYPTION_KEY
docker rm -f "$(name n8n)" >/dev/null 2>&1 || true
docker run -d --name "$(name n8n)" --restart unless-stopped \
  --network "$ALICE_NET_CORE" --ip "$net.70" --network-alias n8n \
  --cap-drop ALL --security-opt no-new-privileges:true --memory 2g --pids-limit 512 \
  -e N8N_ENCRYPTION_KEY -e N8N_DIAGNOSTICS_ENABLED=false -e N8N_PERSONALIZATION_ENABLED=false \
  -e N8N_VERSION_NOTIFICATIONS_ENABLED=false -e N8N_TEMPLATES_ENABLED=false -e N8N_RUNNERS_ENABLED=true \
  -e GENERIC_TIMEZONE="${ALICE_TIMEZONE:-UTC}" -e N8N_EDITOR_BASE_URL="${ALICE_N8N_URL:-}" -e WEBHOOK_URL="${ALICE_N8N_URL:-}" \
  -e HTTP_PROXY=http://proxy:3128 -e HTTPS_PROXY=http://proxy:3128 -e NO_PROXY="localhost,127.0.0.1,ntfy,home-assistant,$net.2" \
  -v "$state:/home/node/.n8n" "$N8N_IMAGE" >/dev/null

# Up only once sign-in is enforced: for a few seconds after /healthz, the REST API answers without an account.
wait_up "n8n module" 180 answers "http://$net.70:5678/rest/workflows" 401
