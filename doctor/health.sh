#!/usr/bin/env bash
# Usage: health.sh check | boot   (run by the systemd units in doctor/)
# check: model-free tests; alerts only when the set of failures changes.
# boot:  alerts when OpenBao is still sealed after a start.
set -uo pipefail
. "$(dirname "$0")/../lib/common.sh"
load_settings

dir=$ALICE_DATA_DIR/ops
mkdir -p "$dir"
push() {  # title priority message
  local token
  token=$(cat "$ALICE_DATA_DIR/ntfy/harness.token") || return 1
  printf 'header = "Authorization: Bearer %s"\n' "$token" \
    | curl -sf -m 15 --retry 6 --retry-delay 10 --retry-all-errors -K - -H "Title: $1" -H "Priority: $2" --data-binary "$3" \
      "http://${ALICE_NET_CORE_SUBNET%.0/24}.80:8080/$ALICE_ALERT_TOPIC" >/dev/null
}

case "${1:-}" in
  check)
    # A periodic vault token expires unless it is renewed.
    if [ "$ALICE_SECRET_STORE" = openbao ] && cli=$(command -v bao || command -v vault); then
      BAO_ADDR=$ALICE_OPENBAO_ADDR VAULT_ADDR=$ALICE_OPENBAO_ADDR "$cli" token renew >/dev/null 2>&1 || true
    fi
    light=()
    for t in open-webui ollama ocr workspace home-assistant n8n ntfy backup security egress; do
      [[ " open-webui ollama security egress $ALICE_MODULES " == *" $t "* ]] && light+=("$t")
    done
    status=0
    ALICE_CHECK_OPTIONAL=1 bash "$ALICE_ROOT/doctor/doctor.sh" "${light[@]}" > "$dir/health.txt" 2>&1 || status=$?
    # Another check is running (an update, most often): this round is skipped.
    [ "$status" -ne 75 ] || exit 0
    if grep -q '^doctor: ' "$dir/health.txt"; then failing=$(sed -n 's/^doctor: failed: //p' "$dir/health.txt")
    else failing="the health check itself (it stopped before the end)"; fi
    [ "$failing" = "$(cat "$dir/failing" 2>/dev/null)" ] && exit 0
    if [ -n "$failing" ]; then
      push "Alice: problem" high "Failing: $failing"$'\n'"$(grep -m5 FAIL "$dir/health.txt")"
    else
      push "Alice: back to normal" default "Every check passes again."
    fi && printf '%s\n' "$failing" > "$dir/failing"
    ;;
  boot)
    [ "$ALICE_SECRET_STORE" = openbao ] || exit 0
    status=$(curl -s -m 5 --retry 12 --retry-delay 5 --retry-all-errors "$ALICE_OPENBAO_ADDR/v1/sys/seal-status")
    grep -Eq '"sealed": *false' <<< "$status" && exit 0
    push "Alice is waiting for unlock" high "The secret store is sealed or not answering: unlock it on the server."
    ;;
  *) die "usage: health.sh check | boot" ;;
esac
