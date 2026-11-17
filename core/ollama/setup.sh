#!/usr/bin/env bash
# Ollama listens on every interface; firewall.sh lets only Open WebUI in.
set -euo pipefail
. "$(dirname "$0")/../../lib/common.sh"
load_settings

pull() { for m in $1; do info "pulling $m"; curl -sf "$ALICE_OLLAMA_URL/api/pull" -d "{\"model\":\"$m\",\"stream\":false}" >/dev/null || die "could not pull $m"; qwen35 "$m"; done; }
# A model pulled from Hugging Face runs on its GGUF chat template, which for the Qwen 3.5 family misses a tool call
# written after a sentence. It gets Ollama's own Qwen 3.5 renderer and parser instead, as Ollama's Qwen models have,
# and the sampling Qwen recommends for the family in thinking mode.
qwen35() {
  [[ $1 == hf.co/* ]] || return 0
  arch=$(curl -sf "$ALICE_OLLAMA_URL/api/show" -d "{\"model\":\"$1\"}" |
    python3 -I -c 'import json, sys; print(json.load(sys.stdin)["model_info"].get("general.architecture", ""))') \
    || die "could not read the format of $1"
  case $arch in qwen35 | qwen35moe) ;; *) return 0 ;; esac
  params='{"stop":["<|im_end|>"],"temperature":1,"top_k":20,"top_p":0.95,"min_p":0}'
  curl -sf "$ALICE_OLLAMA_URL/api/create" -d "{\"model\":\"$1\",\"from\":\"$1\",\"renderer\":\"qwen3.5\",\"parser\":\"qwen3.5\",
    \"parameters\":$params,\"stream\":false}" >/dev/null || die "could not set the Qwen 3.5 format on $1"
}
models="bge-m3 $(preset_models | xargs)"
if [ "$ALICE_OLLAMA_MODE" = external ]; then
  curl -sf -m 5 "$ALICE_OLLAMA_URL/api/version" >/dev/null || die "no Ollama answers at $ALICE_OLLAMA_URL"
  pull "$models"
  info "using the existing Ollama at $ALICE_OLLAMA_URL"
  exit 0
fi
[ "$ALICE_OLLAMA_MODE" = native ] || die "ALICE_OLLAMA_MODE must be native or external"
if [ "$(ollama --version 2>/dev/null | grep -o '[0-9][0-9.]*' | tail -1)" != "$OLLAMA_VERSION" ]; then
  info "installing Ollama $OLLAMA_VERSION"
  fetch "https://raw.githubusercontent.com/ollama/ollama/v$OLLAMA_VERSION/scripts/install.sh" "$OLLAMA_INSTALL_SHA256" \
    "$ALICE_DATA_DIR/ollama/install-$OLLAMA_VERSION.sh"
  sh "$ALICE_DATA_DIR/ollama/install-$OLLAMA_VERSION.sh"
fi
# systemd applies drop-ins in name order, the last value winning: this one comes last.
dropins=/etc/systemd/system/ollama.service.d
mkdir -p "$dropins"
rm -f "$dropins/alice-harness.conf"
sed -e "s/{{MAX_LOADED_MODELS}}/$ALICE_OLLAMA_MAX_LOADED_MODELS/" -e "s/{{NUM_PARALLEL}}/$ALICE_OLLAMA_NUM_PARALLEL/" \
  -e "s/{{CONTEXT_LENGTH}}/${ALICE_OLLAMA_CONTEXT_LENGTH:-65536}/" \
  "$ALICE_ROOT/core/ollama/ollama.conf" > "$dropins/zz-alice-harness.conf"
for f in "$dropins"/*.conf; do
  [ "$f" = "$dropins/zz-alice-harness.conf" ] || ! grep -q OLLAMA_ "$f" || info "note: $f also sets Ollama values; the harness's win"
done
systemctl daemon-reload
systemctl enable --now ollama >/dev/null
systemctl restart ollama
for _ in $(seq 1 30); do curl -sf -m 2 http://127.0.0.1:11434/api/version >/dev/null && break; sleep 1; done

info "models"
pull "$models"
info "Ollama is ready"
