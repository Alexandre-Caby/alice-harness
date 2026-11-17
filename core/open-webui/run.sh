#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/../../lib/common.sh"
load_settings

here=$ALICE_ROOT/core/open-webui
state=$ALICE_DATA_DIR/open-webui
container=$(name openwebui)
core_ip=${ALICE_NET_CORE_SUBNET%.0/24}.2
mkdir -p "$state/data" "$state/patched"

info "approval patch"
docker run --rm --entrypoint cat "$OPENWEBUI_IMAGE" /app/backend/open_webui/utils/tool_permissions.py \
  > "$state/patched/upstream.py"
echo "$OPENWEBUI_APPROVAL_FILE_SHA256  $state/patched/upstream.py" | sha256sum -c --quiet - \
  || die "the upstream approval file changed; review core/open-webui/approval.patch before updating Open WebUI"
patch -s -o "$state/patched/tool_permissions.py" "$state/patched/upstream.py" < "$here/approval.patch" \
  || die "the approval patch does not apply"
grep -q "there is no \"full access\" mode" "$state/patched/tool_permissions.py" || die "the approval patch is missing"

info "settings"
env_files=(--env-file "$here/settings.conf")
for module in $ALICE_MODULES; do
  f=$(module_dir "$module")/openwebui.conf
  [ -f "$f" ] && env_files+=(--env-file "$f")
  # Settings that depend on account ids (workspaces) are generated at deploy time.
  g=$ALICE_DATA_DIR/$module/openwebui.conf
  [ -f "$g" ] && env_files+=(--env-file "$g")
done

info "container"
# Passed through the environment, never as arguments; an empty secret stops here, before the old container goes.
for s in WEBUI_SECRET_KEY WEBUI_ADMIN_EMAIL WEBUI_ADMIN_PASSWORD; do
  v=$(secret "$s")
  [ -n "$v" ] || die "the secret $s is empty"
  export "$s=$v"
done
# Optional sign-in through an OpenID Connect provider: it finds existing accounts by e-mail and never creates one.
oidc=()
if [ -n "${ALICE_OIDC_PROVIDER_URL:-}" ]; then
  [ -n "${ALICE_WEBUI_URL:-}" ] || die "ALICE_OIDC_PROVIDER_URL needs ALICE_WEBUI_URL"
  for s in OAUTH_CLIENT_ID OAUTH_CLIENT_SECRET; do
    v=$(secret "$s")
    [ -n "$v" ] || die "the secret $s is empty"
    export "$s=$v"
  done
  # Behind a TLS-terminating proxy the request arrives as plain http: the redirect address is given, not guessed.
  oidc=(-e OPENID_PROVIDER_URL="$ALICE_OIDC_PROVIDER_URL" -e OAUTH_PROVIDER_NAME="${ALICE_OIDC_NAME:-SSO}"
    -e OPENID_REDIRECT_URI="${ALICE_WEBUI_URL%/}/oauth/oidc/callback"
    -e OAUTH_CLIENT_ID -e OAUTH_CLIENT_SECRET -e ENABLE_OAUTH_SIGNUP=false -e OAUTH_MERGE_ACCOUNTS_BY_EMAIL=true)
fi
url=()
[ -z "${ALICE_WEBUI_URL:-}" ] || url=(-e WEBUI_URL="$ALICE_WEBUI_URL")
# Without it a new chat opens on whichever model comes first, the embedding model for an admin.
default_model=${ALICE_PRESETS%%;*}
default_model=${default_model%%=*}
default_model=${default_model//[[:space:]]/}
docker rm -f "$container" >/dev/null 2>&1 || true
# Wipe the persisted config so the env files win; keep only the MCP connections added in the UI.
if [ -f "$state/data/webui.db" ]; then
  python3 -I -B -c 'import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
db.execute("DELETE FROM config WHERE key <> ?", ("tool_server.connections",))
db.commit()' "$state/data/webui.db"
fi
docker run -d --name "$container" --restart unless-stopped \
  --network "$ALICE_NET_CORE" --ip "$core_ip" \
  --cap-drop ALL --security-opt no-new-privileges:true --memory 4g --pids-limit 512 \
  "${env_files[@]}" \
  -e WEBUI_NAME="$ALICE_WEBUI_NAME" -e DEFAULT_MODELS="$default_model" \
  -e OLLAMA_BASE_URL="$ALICE_OLLAMA_URL" -e RAG_OLLAMA_BASE_URL="$ALICE_OLLAMA_URL" \
  -e WEBUI_SECRET_KEY -e WEBUI_ADMIN_EMAIL -e WEBUI_ADMIN_PASSWORD "${oidc[@]}" "${url[@]}" \
  -v "$state/data:/app/backend/data" \
  -v "$state/patched/tool_permissions.py:/app/backend/open_webui/utils/tool_permissions.py:ro" \
  "$OPENWEBUI_IMAGE" >/dev/null

# Web search needs the egress network; the workspaces are on theirs.
docker network connect "$ALICE_NET_EGRESS" "$container"
join_workspaces "$container" 2

wait_up "Open WebUI" 240 answers "http://$core_ip:8080/health" 200
