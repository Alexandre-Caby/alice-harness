#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/../../lib/common.sh"
load_settings

docker build -q -t "$(name egress):local" --build-arg PYTHON_IMAGE="$PYTHON_IMAGE" "$ALICE_ROOT/security/egress" >/dev/null
info "egress proxy built"
