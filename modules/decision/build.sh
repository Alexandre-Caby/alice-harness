#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/../../lib/common.sh"
load_settings

fetch "$DECISION_MODEL_URL" "$DECISION_MODEL_SHA256" "$ALICE_DATA_DIR/decision/models/$(basename "$DECISION_MODEL_URL")"
info "decision model ready"
