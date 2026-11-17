#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/../lib/common.sh"
load_settings

# Containers without a fixed address get one from .128 up, so they never take a fixed one (.2 to .90).
create() {  # name subnet bridge [--internal]
  local have
  if have=$(docker network inspect "$1" -f '{{range .IPAM.Config}}{{.Subnet}}{{end}} {{.Internal}}' 2>/dev/null); then
    [ "$have" = "$2 $([ -n "${4:-}" ] && echo true || echo false)" ] || die "network $1 exists with other settings ($have)"
    return 0
  fi
  docker network create "${@:4}" --subnet "$2" --ip-range "${2%.0/24}.128/25" --gateway "${2%.0/24}.1" \
    -o com.docker.network.bridge.name="$3" "$1" >/dev/null
}
create "$ALICE_NET_CORE" "$ALICE_NET_CORE_SUBNET" "br-${ALICE_PREFIX}-core" --internal
create "$ALICE_NET_EGRESS" "$ALICE_NET_EGRESS_SUBNET" "br-${ALICE_PREFIX}-out"
create "$ALICE_NET_WORKSPACE" "$ALICE_NET_WORKSPACE_SUBNET" "br-${ALICE_PREFIX}-ws" --internal
info "networks ready"
