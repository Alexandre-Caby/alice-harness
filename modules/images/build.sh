#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/../../lib/common.sh"
load_settings

models=$ALICE_DATA_DIR/images/models
fetch "$IMAGES_DIFFUSION_URL" "$IMAGES_DIFFUSION_SHA256" "$models/$(basename "$IMAGES_DIFFUSION_URL")"
fetch "$IMAGES_TEXT_ENCODER_URL" "$IMAGES_TEXT_ENCODER_SHA256" "$models/$(basename "$IMAGES_TEXT_ENCODER_URL")"
fetch "$IMAGES_VAE_URL" "$IMAGES_VAE_SHA256" "$models/$(basename "$IMAGES_VAE_URL")"
docker build -q -t "$(name images):local" --build-arg SDCPP_COMMIT="$SDCPP_COMMIT" --build-arg UBUNTU_IMAGE="$UBUNTU_IMAGE" --build-arg BACKEND="$ALICE_BACKEND" \
  "$ALICE_ROOT/modules/images" >/dev/null
info "images module built"
