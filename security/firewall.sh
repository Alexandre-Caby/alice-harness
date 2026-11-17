#!/usr/bin/env bash
# Rules are tagged alice-harness-<prefix> so uninstall removes exactly these.
set -euo pipefail
. "$(dirname "$0")/../lib/common.sh"
load_settings

command -v ufw >/dev/null || die "ufw is not installed"
ufw status verbose | grep "deny (incoming)" >/dev/null || die "the firewall must deny incoming traffic by default"
core=br-${ALICE_PREFIX}-core
out=br-${ALICE_PREFIX}-out
ws=br-${ALICE_PREFIX}-ws
webui=${ALICE_NET_CORE_SUBNET%.0/24}.2

# ufw refuses "insert 1" while it has no rule yet.
first() { if ufw status numbered | grep '^\[' >/dev/null; then ufw insert 1 "$@"; else ufw "$@"; fi; }
first deny in on "$out" comment "alice-harness-$ALICE_PREFIX" >/dev/null
first deny in on "$core" comment "alice-harness-$ALICE_PREFIX" >/dev/null
first deny in on "$ws" comment "alice-harness-$ALICE_PREFIX" >/dev/null
port=${ALICE_OLLAMA_URL##*:}
first allow in on "$core" from "$webui" to any port "${port%%/*}" proto tcp comment "alice-harness-$ALICE_PREFIX" >/dev/null
info "firewall ready: Ollama reachable from Open WebUI only"
