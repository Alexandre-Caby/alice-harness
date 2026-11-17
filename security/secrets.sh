#!/usr/bin/env bash
# Usage: secrets.sh init | set NAME
set -euo pipefail
. "$(dirname "$0")/../lib/common.sh"
load_settings

[ "$ALICE_SECRET_STORE" = file ] || die "the secret store is $ALICE_SECRET_STORE: set the secrets with its own tool"
f=$ALICE_SECRETS_FILE
put() {
  umask 077
  mkdir -p "$(dirname "$f")"
  touch "$f"
  grep -v "^$1=" "$f" > "$f.new" || true
  printf '%s=%s\n' "$1" "$2" >> "$f.new"
  mv "$f.new" "$f"
  chmod 600 "$f"
}
case "${1:-}" in
  init)
    grep -q '^WEBUI_SECRET_KEY=' "$f" 2>/dev/null || put WEBUI_SECRET_KEY "$(openssl rand -hex 32)"
    grep -q '^N8N_ENCRYPTION_KEY=' "$f" 2>/dev/null || put N8N_ENCRYPTION_KEY "$(openssl rand -hex 32)"
    if ! grep -q '^WEBUI_ADMIN_EMAIL=' "$f" 2>/dev/null; then
      # Passed by the installer, asked otherwise.
      email=${ALICE_ADMIN_EMAIL:-}
      password=${ALICE_ADMIN_PASSWORD:-}
      [ -n "$email" ] || read -r -p "Administrator e-mail: " email
      if [ -z "$password" ]; then read -r -s -p "Administrator password (12 characters or more): " password; echo; fi
      [ ${#password} -ge 12 ] || die "the password needs at least 12 characters"
      put WEBUI_ADMIN_EMAIL "$email"
      put WEBUI_ADMIN_PASSWORD "$password"
    fi
    info "secrets ready in $f"
    ;;
  set)
    [ -n "${2:-}" ] || die "usage: secrets.sh set NAME"
    read -r -s -p "$2: " value; echo
    put "$2" "$value"
    ;;
  *) die "usage: secrets.sh init | set NAME" ;;
esac
