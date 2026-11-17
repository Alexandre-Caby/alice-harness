#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/../../lib/common.sh"
load_settings

python3 -I -B "$ALICE_ROOT/modules/tts/fetch_model.py" "$TTS_MODEL_REPO" "$TTS_MODEL_REVISION" "$TTS_MODEL_SHA256" \
  "$ALICE_DATA_DIR/tts/model" || die "voice model download failed"
docker build -q -t "$(name tts):local" --build-arg QWEN_TTS_COMMIT="$QWEN_TTS_COMMIT" --build-arg UBUNTU_IMAGE="$UBUNTU_IMAGE" "$ALICE_ROOT/modules/tts" >/dev/null
info "tts module built"
