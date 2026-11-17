#!/usr/bin/env bash
# Reached from outside only through a proxy you set up; ntfy never goes out.
set -euo pipefail
. "$(dirname "$0")/../../lib/common.sh"
load_settings

state=$ALICE_DATA_DIR/ntfy
net=${ALICE_NET_CORE_SUBNET%.0/24}
mkdir -p "$state/data"
sed "s#{{BASE_URL}}#${ALICE_NTFY_URL:-http://$net.80:8080}#" "$ALICE_ROOT/modules/ntfy/server.yml" > "$state/server.yml"
chown -R 65534:65534 "$state/data"

docker rm -f "$(name ntfy)" >/dev/null 2>&1 || true
docker run -d --name "$(name ntfy)" --restart unless-stopped \
  --network "$ALICE_NET_CORE" --ip "$net.80" --network-alias ntfy \
  --cap-drop ALL --security-opt no-new-privileges:true --memory 256m --pids-limit 128 --user 65534:65534 \
  -v "$state/server.yml:/etc/ntfy/server.yml:ro" -v "$state/data:/var/lib/ntfy" "$NTFY_IMAGE" serve >/dev/null

wait_up ntfy 30 answers "http://$net.80:8080/v1/health" 200

# Write-only account for the harness. Token kept on disk so alerts still go out while the vault is sealed.
if [ ! -s "$state/harness.token" ]; then
  NTFY_PASSWORD=$(openssl rand -hex 24)
  export NTFY_PASSWORD
  if docker exec "$(name ntfy)" ntfy user list 2>&1 | grep '^user harness ' >/dev/null; then
    docker exec -e NTFY_PASSWORD "$(name ntfy)" ntfy user change-pass harness >/dev/null
  else
    docker exec -e NTFY_PASSWORD "$(name ntfy)" ntfy user add harness >/dev/null
  fi
  unset NTFY_PASSWORD
  docker exec "$(name ntfy)" ntfy access harness '*' write-only >/dev/null
  token=$(docker exec "$(name ntfy)" ntfy token add harness | grep -o 'tk_[A-Za-z0-9]*' | head -1)
  [ -n "$token" ] || die "ntfy gave no token for the harness account"
  (umask 077; echo "$token" > "$state/harness.token")
fi
info "ntfy module is ready"
