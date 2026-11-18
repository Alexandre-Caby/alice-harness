#!/usr/bin/env bash
# Usage: doctor.sh [label...]   e.g. doctor.sh soul approvals
# Runs as root, exits non-zero on any failure. In a terminal, hands over to install.sh for the progress bar.
[ -t 1 ] && exec bash "$(dirname "$0")/../install.sh" check "$@"
set -uo pipefail
. "$(dirname "$0")/../lib/common.sh"
load_settings

net=${ALICE_NET_CORE_SUBNET%.0/24}
export ALICE_TEST_URL="http://$net.2:8080"
ALICE_TEST_ADMIN_EMAIL=$(secret WEBUI_ADMIN_EMAIL)
ALICE_TEST_ADMIN_PASSWORD=$(secret WEBUI_ADMIN_PASSWORD)
export ALICE_TEST_ADMIN_EMAIL ALICE_TEST_ADMIN_PASSWORD

declare -A url=(
  [decision]="http://$net.10:8096" [ocr]="http://$net.30:9998"
  [tts]="http://$net.40:7863 $(has stt && echo "http://$net.50:7864")" [stt]="http://$net.50:7864 $ALICE_DATA_DIR/stt/terms/terms.txt"
  [images]="http://$net.60:7860" [n8n]="http://$net.70:5678 $(name n8n)" [ntfy]="http://$net.80:8080 $(name ntfy)"
)
# No secrets in the report, so it can be world-readable.
report=$ALICE_DATA_DIR/doctor/last.txt
mkdir -p "$(dirname "$report")"
# One check at a time: two would share the test workspace and the report. The hourly check gives way (exit 75).
exec 9> "$ALICE_DATA_DIR/doctor/lock"
if ! flock -n 9; then
  [ -z "${ALICE_CHECK_OPTIONAL:-}" ] || exit 75
  echo "waiting for another check to finish"
  flock 9
fi
: > "$report"
chmod 644 "$report"
exec > >(tee "$report") 2>&1
failed=()
only=" $* "
run() {  # label, command...
  [ "$only" = "  " ] || [[ "$only" == *" $1 "* ]] || return 0
  local start=$SECONDS
  "${@:2}" || failed+=("$1")
  printf '  %s s\n\n' "$((SECONDS - start))"
}
run open-webui python3 -I -B "$ALICE_ROOT/core/open-webui/test.py" "$(name openwebui)"
# The doctor runs on the host.
run ollama python3 -I -B "$ALICE_ROOT/core/ollama/test.py" "${ALICE_OLLAMA_URL/172.*:/127.0.0.1:}"
run soul python3 -I -B "$ALICE_ROOT/core/soul/test.py"
for module in $ALICE_MODULES; do
  read -ra args <<< "${url[$module]:-}"
  run "$module" python3 -I -B "$(module_dir "$module")/test.py" "${args[@]}"
done
# The gate is exercised through the test workspace.
if has decision && has workspace; then run approvals python3 -I -B "$ALICE_ROOT/tests/approvals.py" "${ALICE_PRESETS%%=*}"; fi
run security python3 -I -B "$ALICE_ROOT/security/test.py"
run egress python3 -I -B "$ALICE_ROOT/security/egress/test.py"

[ ${#failed[@]} -gt 0 ] || { echo "doctor: everything passed"; exit 0; }
echo "doctor: failed: ${failed[*]}"
exit 1
