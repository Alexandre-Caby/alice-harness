#!/usr/bin/env bash
# Presets go through the API, so they are written once Open WebUI is up.
set -euo pipefail
. "$(dirname "$0")/../../lib/common.sh"
load_settings

bash "$ALICE_ROOT/core/open-webui/run.sh"
ALICE_TEST_URL="http://${ALICE_NET_CORE_SUBNET%.0/24}.2:8080" ALICE_TEST_ADMIN_EMAIL="$(secret WEBUI_ADMIN_EMAIL)" \
  ALICE_TEST_ADMIN_PASSWORD="$(secret WEBUI_ADMIN_PASSWORD)" python3 -I -B "$ALICE_ROOT/core/soul/presets.py"
