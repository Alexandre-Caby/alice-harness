#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/../../lib/common.sh"
load_settings

command -v runsc >/dev/null || die "gVisor (runsc) is not installed"
docker info --format '{{json .Runtimes}}' | grep '"runsc"' >/dev/null || die "gVisor is not registered as a Docker runtime"
docker build -q -t "$(name workspace):local" --build-arg OPEN_TERMINAL_IMAGE="$OPEN_TERMINAL_IMAGE" \
  "$ALICE_ROOT/modules/workspace" >/dev/null
info "workspace module built"
