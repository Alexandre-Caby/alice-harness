#!/usr/bin/env bash
# Installed only when ALICE_ALERT_TOPIC is set and ntfy is enabled, removed otherwise.
set -euo pipefail
. "$(dirname "$0")/../lib/common.sh"
load_settings

topic=${ALICE_ALERT_TOPIC:-}
has ntfy || topic=
systemctl disable --now "$ALICE_PREFIX-health.timer" "$ALICE_PREFIX-unlock-alert.service" >/dev/null 2>&1 || true
for u in health.service health.timer unlock-alert.service; do
  rm -f "/etc/systemd/system/$ALICE_PREFIX-$u"
  [ -z "$topic" ] || sed "s#{{ROOT}}#$ALICE_ROOT#" "$ALICE_ROOT/doctor/$u" > "/etc/systemd/system/$ALICE_PREFIX-$u"
done
systemctl daemon-reload
if [ -n "$topic" ]; then
  systemctl enable --now "$ALICE_PREFIX-health.timer" >/dev/null 2>&1
  systemctl enable "$ALICE_PREFIX-unlock-alert.service" >/dev/null 2>&1
  info "health alerts go to the ntfy topic $ALICE_ALERT_TOPIC"
fi
