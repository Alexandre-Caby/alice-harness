#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/../../lib/common.sh"
load_settings

fetch "$STT_MODEL_URL" "$STT_MODEL_SHA256" "$ALICE_DATA_DIR/stt/models/$(basename "$STT_MODEL_URL")"
fetch "$STT_ENCODER_URL" "$STT_ENCODER_SHA256" "$ALICE_DATA_DIR/stt/models/$(basename "$STT_ENCODER_URL")"
docker build -q -t "$(name stt-model):local" --build-arg NEMO_SPEECH_COMMIT="$NEMO_SPEECH_COMMIT" --build-arg UBUNTU_IMAGE="$UBUNTU_IMAGE" \
  --build-arg BACKEND="$ALICE_BACKEND" "$ALICE_ROOT/modules/stt" >/dev/null
docker build -q -t "$(name stt):local" --build-arg PYTHON_IMAGE="$PYTHON_IMAGE" "$ALICE_ROOT/modules/stt/shim" >/dev/null
info "stt module built"
