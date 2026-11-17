#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/../../lib/common.sh"
load_settings

net=${ALICE_NET_CORE_SUBNET%.0/24}
voice=() args=()
if [ -n "${ALICE_TTS_VOICE_FILE:-}" ]; then
  [ -r "$ALICE_TTS_VOICE_FILE" ] || die "voice file $ALICE_TTS_VOICE_FILE is not readable"
  voice=(-v "$ALICE_TTS_VOICE_FILE:/voice.qvoice:ro")
  args=(--load-voice /voice.qvoice --icl-only)
fi

docker rm -f "$(name tts)" >/dev/null 2>&1 || true
docker run -d --name "$(name tts)" --restart unless-stopped \
  --network "$ALICE_NET_CORE" --ip "$net.40" --network-alias tts \
  --cap-drop ALL --security-opt no-new-privileges:true --read-only --memory 6g --pids-limit 256 --cpus 8 \
  -v "$ALICE_DATA_DIR/tts/model:/model:ro" "${voice[@]}" "$(name tts):local" \
  -d /model --int8 -j 0 -l "${ALICE_TTS_LANGUAGE:-English}" "${args[@]}" --serve 7863 >/dev/null

join_workspaces "$(name tts)" 40
wait_up "tts module" 120 answers "http://$net.40:7863/v1/speakers"
