ALICE_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "== $*"; }

load_settings() {
  [ -f "$ALICE_ROOT/versions.lock" ] || die "versions.lock is missing"
  [ -f "$ALICE_ROOT/machine.env" ] || die "machine.env is missing: run ./install.sh first"
  set -a
  . "$ALICE_ROOT/versions.lock"
  . "$ALICE_ROOT/machine.env"
  : "${ALICE_NET_WORKSPACE:=$ALICE_PREFIX-workspace}" "${ALICE_NET_WORKSPACE_SUBNET:=10.52.0.0/24}"
  set +a
}

# Workspaces have their own internal network: a service they may call joins it with the same last number.
join_workspaces() {  # container number
  docker network connect --ip "${ALICE_NET_WORKSPACE_SUBNET%.0/24}.$2" "$ALICE_NET_WORKSPACE" "$1"
}

# Never log the output.
secret() {
  local name=$1
  case "${ALICE_SECRET_STORE:-file}" in
    file)
      [ -r "$ALICE_SECRETS_FILE" ] || die "secrets file $ALICE_SECRETS_FILE is not readable (run as root)"
      grep -m1 "^${name}=" "$ALICE_SECRETS_FILE" | cut -d= -f2-
      ;;
    openbao)
      local cli
      cli=$(command -v bao || command -v vault) || die "neither the bao nor the vault client is installed"
      BAO_ADDR=$ALICE_OPENBAO_ADDR VAULT_ADDR=$ALICE_OPENBAO_ADDR "$cli" kv get -field="$name" "$ALICE_OPENBAO_PATH"
      ;;
    command)
      # See security/SECRETS.md
      bash -c "${ALICE_SECRET_COMMAND//\{name\}/$name}"
      ;;
    *) die "unknown secret store: $ALICE_SECRET_STORE" ;;
  esac
}

name() { echo "${ALICE_PREFIX}-$1"; }
module_dir() { echo "$ALICE_ROOT/modules/$1"; }
has() { [[ " $ALICE_MODULES " == *" $1 "* ]]; }
# The Ollama models of the presets ("id=model|label;...").
preset_models() { tr ';' '\n' <<< "$ALICE_PRESETS" | sed -n 's/^[^=]*=\([^|]*\).*/\1/p'; }

# wait_up LABEL SECONDS COMMAND...: the command succeeds once the service answers.
wait_up() {
  local label=$1 end=$((SECONDS + $2))
  shift 2
  until "$@" >/dev/null 2>&1; do
    [ "$SECONDS" -lt "$end" ] || die "$label did not come up"
    sleep 2
  done
  info "$label is up"
}
# answers URL [CODE]: any HTTP answer, or exactly that status.
answers() {
  local code
  code=$(curl -s -m 2 -o /dev/null -w '%{http_code}' "$1") && [ "$code" = "${2:-$code}" ]
}

# fetch URL SHA256 DEST
fetch() {
  local url=$1 sum=$2 dest=$3
  if [ -s "$dest" ] && echo "$sum  $dest" | sha256sum -c --quiet - 2>/dev/null; then return 0; fi
  mkdir -p "$(dirname "$dest")"
  curl -fsSL --retry 3 --speed-limit 10000 --speed-time 120 -o "$dest.part" "$url" || die "download failed: $url"
  echo "$sum  $dest.part" | sha256sum -c --quiet - || { rm -f "$dest.part"; die "hash mismatch: $(basename "$dest")"; }
  mv "$dest.part" "$dest"
}

# Sets GPU to the docker run arguments that give a container the GPU.
gpu_args() {
  case "$ALICE_BACKEND" in
    vulkan | rocm) GPU=(--device /dev/dri --group-add "$(getent group render | cut -d: -f3)" --group-add "$(getent group video | cut -d: -f3)") ;;
    cuda) GPU=(--gpus all) ;;
    cpu) GPU=() ;;
    *) die "unknown backend $ALICE_BACKEND" ;;
  esac
}
