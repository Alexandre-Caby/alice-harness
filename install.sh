#!/usr/bin/env bash
# Usage: sudo ./install.sh [update | modules | module NAME | people | assistant | alerts | check | uninstall]
# No argument: onboarding on a fresh machine, menu otherwise.
set -euo pipefail
cd "$(dirname "$0")"
. lib/common.sh
. lib/ui.sh
[ "$(id -u)" -eq 0 ] || die "run as root: sudo ./install.sh"
mkdir -p /var/log/alice-harness
UI_LOG=/var/log/alice-harness/install-$(date +%Y%m%d-%H%M%S).log
: > "$UI_LOG"
chmod 600 "$UI_LOG"
ln -sf "$UI_LOG" /var/log/alice-harness/last.log
# Keep the last five logs.
find /var/log/alice-harness -name 'install-*.log' | sort -r | tail -n +6 | xargs -r rm -f
set -a
. ./versions.lock
set +a
ui_init

declare -A answers
# Read the way the scripts will read it: machine.env is sourced.
read_key() { [ -f "$1" ] || return 0; (set +eu; set -a; . "./$1" >/dev/null 2>&1; printf '%s\n' "${!2:-}"); }
current() { read_key machine.env "$1"; }
example() { read_key machine.env.example "$1"; }
value() {
  if [ -n "${answers[$1]+set}" ]; then echo "${answers[$1]}"
  elif [ -f machine.env ] && grep -q "^$1=" machine.env; then current "$1"
  else example "$1"; fi
}

# Regenerate machine.env from the template: answer, else current value, else default.
save_settings() {
  local tmp line key v known=" "
  tmp=$(mktemp)
  while IFS= read -r line; do
    if [[ $line =~ ^[A-Z0-9_]+= ]]; then
      key=${line%%=*}
      known+="$key "
      v=$(value "$key")
      v=${v//\\/\\\\}; v=${v//\"/\\\"}; v=${v//\$/\\\$}; v=${v//\`/\\\`}
      printf '%s="%s"\n' "$key" "$v"
    else
      echo "$line"
    fi
  done < machine.env.example > "$tmp"
  # Settings that are not in the template are kept as written.
  if [ -f machine.env ]; then
    grep -E '^[A-Z0-9_]+=' machine.env | while IFS= read -r line; do
      [[ $known == *" ${line%%=*} "* ]] || echo "$line"
    done > "$tmp.extra" || true
    if [ -s "$tmp.extra" ]; then printf '\n# Not in the template\n' >> "$tmp"; cat "$tmp.extra" >> "$tmp"; fi
    rm -f "$tmp.extra"
  fi
  # No secret in it: readable, but only root may change what the scripts source as root.
  install -m 644 -o root -g root "$tmp" machine.env
  rm -f "$tmp"
}

MODULE_ORDER="ocr decision ntfy workspace images stt tts home-assistant n8n backup"
declare -A ABOUT=(
  [ocr]="reads documents and photos|~1 GB"
  [decision]="judges tool calls before they run|~23 GB"
  [ntfy]="phone notifications|~50 MB"
  [workspace]="files and code: one workspace per person|~120 MB each"
  [images]="creates and edits images|~12 GB"
  [stt]="dictation: speak and it writes|~18 GB"
  [tts]="voice|~3 GB"
  [home-assistant]="home automation with its own page|~1 GB"
  [n8n]="automations|~1 GB"
  [backup]="nightly backup of the data and settings|a few GB"
)
# The modules above first, in their order, then any other folder of modules/ with a run.sh.
available_modules() {
  local m d
  for m in $MODULE_ORDER; do if [ -f "$(module_dir "$m")/run.sh" ]; then echo "$m"; fi; done
  for d in modules/*/; do
    m=$(basename "$d")
    if [ -f "$d/run.sh" ] && [[ " $MODULE_ORDER " != *" $m "* ]]; then echo "$m"; fi
  done
}

discover() {
  INSTALLED='' PARTIAL=''
  local os ram gpu missing=() prefix
  prefix=$(current ALICE_PREFIX)
  # A core network without Open WebUI is an unfinished installation.
  if [ -n "$prefix" ]; then
    if [ -n "$(docker ps -aq --filter "name=^$prefix-openwebui$" 2>/dev/null)" ]; then INSTALLED=1
    elif docker network ls --format '{{.Name}}' 2>/dev/null | grep -x "$(current ALICE_NET_CORE)" >/dev/null; then INSTALLED=1 PARTIAL=1; fi
  fi
  ui_wait "Getting to know your machine" docker info || missing+=("a running Docker")
  os=$(. /etc/os-release && echo "$PRETTY_NAME")
  ram=$(awk '/MemTotal/ {printf "%d GB", $2 / 1048576}' /proc/meminfo)
  if command -v nvidia-smi >/dev/null; then gpu="NVIDIA GPU (CUDA)"; BACKEND=cuda
  elif ls /dev/dri/renderD* >/dev/null 2>&1; then gpu="GPU (Vulkan)"; BACKEND=vulkan
  else gpu="no GPU (CPU only, slow)"; BACKEND=cpu; fi
  for c in docker ufw curl python3 openssl patch sha256sum ss setsid; do command -v "$c" >/dev/null || missing+=("$c"); done
  UI_MACHINE="$os · $ram · $gpu"
  ui_ok "$UI_MACHINE"
  if [ ${#missing[@]} -gt 0 ]; then
    ui_fail "Missing: ${missing[*]}"
    ui_note "Install them first (Docker: docs.docker.com/engine/install), then run this again."
    exit 1
  fi
  if ! ufw status verbose | grep "deny (incoming)" >/dev/null; then
    ui_fail "The firewall is off or lets incoming traffic in"
    ui_note "Turn it on with incoming traffic denied (sudo ufw default deny incoming, then sudo ufw enable; allow SSH first)."
    exit 1
  fi
  ui_ok "Docker and the firewall are ready"
  if command -v runsc >/dev/null; then ui_ok "gVisor is ready for the workspaces"; else ui_warn "No gVisor: the workspaces will not work"; fi
  VAULT=
  for addr in ${BAO_ADDR:-} ${VAULT_ADDR:-} http://127.0.0.1:8200; do
    if curl -s -m 2 -o /dev/null "$addr/v1/sys/health"; then VAULT=$addr; break; fi
  done
  if [ -n "$VAULT" ]; then ui_ok "A secret vault answers at $VAULT"; fi
  if [ -n "$PARTIAL" ]; then ui_warn "The installation '$prefix' stopped before the end: \"Update everything\" finishes it"
  elif [ -n "$INSTALLED" ]; then ui_ok "A.L.I.C.E. Harness is already installed here"; fi
}

# ask_password PROMPT MIN_LENGTH
ask_password() {
  local first second
  while :; do
    first=$(ui_secret "$1") || exit 1
    if [ ${#first} -lt "$2" ]; then ui_warn "At least $2 characters, please." >&2; continue; fi
    second=$(ui_secret "Once more, to be sure") || exit 1
    [ "$first" = "$second" ] && break
    ui_warn "The two do not match." >&2
  done
  echo "$first"
}

ask_secrets() {
  local file="A protected file on this machine (simplest)" vault="A vault I already run (OpenBao or HashiCorp Vault)"
  local install="Install OpenBao first" other="Another secret store (a command that prints a secret)" choice
  ui_say "Where should the secrets live? (keys and accounts)"
  if [ -n "$VAULT" ]; then
    choice=$("$GUM" choose "$vault" "$file" "$other")
  else
    choice=$("$GUM" choose "$file" "$vault" "$install" "$other")
  fi
  case "$choice" in
    "$file")
      answers[ALICE_SECRET_STORE]="file"
      if grep -qs '^WEBUI_ADMIN_EMAIL=' "$(value ALICE_SECRETS_FILE)"; then
        ui_ok "The secrets file already holds an administrator account: it is kept"
        return
      fi
      while :; do
        answers[ALICE_ADMIN_EMAIL_NEW]=$(ui_ask "E-mail of the administrator account" "${answers[ALICE_ADMIN_EMAIL_NEW]:-}")
        [[ ${answers[ALICE_ADMIN_EMAIL_NEW]} =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]] && break
        ui_warn "That does not look like an e-mail address."
      done
      answers[ALICE_ADMIN_PASSWORD_NEW]=$(ask_password "Its password (12 characters or more)" 12)
      ;;
    "$vault")
      answers[ALICE_SECRET_STORE]=openbao
      answers[ALICE_OPENBAO_ADDR]=$(ui_ask "Address of the vault" "${VAULT:-$(value ALICE_OPENBAO_ADDR)}")
      answers[ALICE_OPENBAO_PATH]=$(ui_ask "Path of the harness secrets in the vault" "$(value ALICE_OPENBAO_PATH)")
      ui_note "The secrets the harness needs, and how to put them there: security/SECRETS.md"
      ;;
    "$install")
      ui_card "Install OpenBao and put the harness secrets in it, then run this again:" \
        "security/SECRETS.md, section \"Installing OpenBao\"." "Or choose the protected file now, and move later."
      exit 0
      ;;
    "$other")
      answers[ALICE_SECRET_STORE]="command"
      answers[ALICE_SECRET_COMMAND]=$(ui_ask "Command that prints one secret ({name} stands for its name)" \
        "$(value ALICE_SECRET_COMMAND)")
      ui_note "The secrets it must give, with examples: security/SECRETS.md"
      ;;
  esac
}

# Probe 127.0.0.1: the harness network and its gateway address may not exist yet.
ask_ollama() {
  local gateway port ports=() found=() choice setup
  gateway=http://$(value ALICE_NET_CORE_SUBNET | sed 's|\.0/24$|.1|')
  port=$(value ALICE_OLLAMA_URL)
  port=${port##*:}
  for p in "$port" 11434; do
    if [[ " ${ports[*]} " != *" $p "* ]] && curl -sf -m 3 "http://127.0.0.1:$p/api/version" >/dev/null; then
      ports+=("$p")
      if ss -ltnH "sport = :$p" | grep '127\.0\.0\.1:' >/dev/null; then
        ui_warn "The Ollama on port $p listens only on 127.0.0.1: the containers cannot reach it (OLLAMA_HOST=0.0.0.0:$p)"
      fi
      found+=("Use the Ollama already running on port $p (left as it is)")
    fi
  done
  setup="Let the harness set up Ollama $OLLAMA_VERSION (installs it and restarts the system's Ollama)"
  if [ ${#found[@]} -eq 0 ]; then
    ui_note "No Ollama runs here: the harness will install Ollama $OLLAMA_VERSION."
    choice=$setup
  else
    if [ "$(value ALICE_OLLAMA_MODE)" = native ]; then
      choice=$("$GUM" choose --header "Ollama, which runs the models:" "$setup" "${found[@]}")
    else
      choice=$("$GUM" choose --header "Ollama, which runs the models:" "${found[@]}" "$setup")
    fi
  fi
  if [ "$choice" = "$setup" ]; then
    answers[ALICE_OLLAMA_MODE]=native
    answers[ALICE_OLLAMA_URL]=$gateway:11434
  else
    port=$(echo "$choice" | sed -n 's/.*on port \([0-9]*\).*/\1/p')
    answers[ALICE_OLLAMA_MODE]=external
    answers[ALICE_OLLAMA_URL]=$gateway:$port
  fi
}

ask_soul() {
  local generic="The generic soul" read="Read the generic soul first" write="Write my own now (opens an editor)"
  local file="Use a file I already have" choice path own
  own=$(value ALICE_DATA_DIR)/soul/SOUL.md
  while :; do
    choice=$("$GUM" choose --header "Its character and its rules (the soul):" "$generic" "$read" "$write" "$file")
    case "$choice" in
      "$read") "$GUM" pager < core/soul/SOUL.md ;;
      "$generic") answers[ALICE_SOUL_FILE]=""; return ;;
      "$write")
        if [ ! -f "$own" ]; then
          install -d "$(dirname "$own")"
          cp core/soul/SOUL.md "$own"
        fi
        "$(command -v nano || command -v vi)" "$own"
        answers[ALICE_SOUL_FILE]=$own
        return
        ;;
      "$file")
        path=$(value ALICE_SOUL_FILE)
        while :; do
          path=$(ui_ask "Path of your soul file (from the harness folder, or a full path)" "$path")
          [ -f "$path" ] && break
          ui_warn "No file at '$path'."
        done
        answers[ALICE_SOUL_FILE]=${path#"$PWD"/}
        return
        ;;
    esac
  done
}

# Presets come from a list: the defaults of the template, the current ones, and any Ollama model typed in.
ask_models() {
  local entry model items=() selected=() chosen line other="Another Ollama model…" presets=() id
  declare -A by_line=()
  for entry in $(printf '%s;%s' "$(value ALICE_PRESETS)" "$(example ALICE_PRESETS)" | tr ';' '\n' | tr ' ' '\a' | awk 'NF && !seen[$0]++'); do
    entry=${entry//$'\a'/ }
    model=$(ALICE_PRESETS=$entry preset_models)
    [ -z "${by_line[$model]+set}" ] || continue
    line=$(printf '%-52s %s' "$model" "$(echo "$entry" | cut -d'|' -f2)")
    by_line[$line]=$entry
    by_line[$model]=1
    items+=("$line")
    if [[ ";$(value ALICE_PRESETS);" == *";$entry;"* ]]; then selected+=("$line"); fi
  done
  while :; do
    chosen=$("$GUM" choose --no-limit --no-show-help --header "Chat models: one or several (space to pick, enter to go on); the first is the default" \
      --selected "$(IFS=,; echo "${selected[*]}")" "${items[@]}" "$other")
    presets=()
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      if [ "$line" = "$other" ]; then
        model=$(ui_ask "Ollama model name (for example qwen3:8b, or hf.co/user/repo:quantisation)" "")
        [ -n "$model" ] || continue
        id=alice-$(echo "$model" | tr '[:upper:]' '[:lower:]' | sed 's/^hf\.co\///; s/[^a-z0-9]\{1,\}/-/g; s/^-//; s/-$//')
        presets+=("$id=$model|$model")
      else
        presets+=("${by_line[$line]}")
      fi
    done <<< "$chosen"
    [ ${#presets[@]} -gt 0 ] && break
    ui_warn "Pick at least one model."
  done
  answers[ALICE_PRESETS]=$(IFS=';'; echo "${presets[*]}")
}

ask_assistant() {
  recap; ask_soul
  recap; ask_ollama
  recap; ask_models
}

# Shown above every question: what is already decided, in a few lines.
recap() {
  [ -t 1 ] || return 0
  clear
  printf '\033[1;38;5;%smA.L.I.C.E. Harness\033[0m\033[38;5;%sm · %s\033[0m\n\n' "$UI_MAIN" "$UI_SOFT" "${UI_MACHINE:-}"
  local k v
  for k in ALICE_PREFIX:Name ALICE_DATA_DIR:Data ALICE_SECRET_STORE:Secrets ALICE_SOUL_FILE:Soul ALICE_OLLAMA_MODE:Ollama \
    ALICE_PRESETS:Models ALICE_MODULES:Modules ALICE_OCR_LANGUAGES:Documents ALICE_STT_LANGUAGE:Speech ALICE_TIMEZONE:"Time zone"; do
    [ -n "${answers[${k%%:*}]+set}" ] || continue
    v=${answers[${k%%:*}]}
    case ${k%%:*} in
      ALICE_SOUL_FILE) v=${v:-generic} ;;
      ALICE_PRESETS) v=$(ALICE_PRESETS=$v preset_models | paste -sd, - | sed 's/,/, /g') ;;
      ALICE_OCR_LANGUAGES) v=${v//+/, } ;;
    esac
    printf '  \033[38;5;%sm%-10s\033[0m \033[38;5;%sm%s\033[0m\n' "$UI_SOFT" "${k#*:}" "$UI_TEXT" "$(ui_cut "$v")"
  done
  echo
}

ask_modules() {
  local items=() selected=() m line chosen
  for m in $(available_modules); do
    line=$(printf '%-15s %-45s %s' "$m" "$(echo "${ABOUT[$m]:-}" | cut -d'|' -f1)" "$(echo "${ABOUT[$m]:-}" | cut -s -d'|' -f2)")
    items+=("$line")
    if [[ " $(value ALICE_MODULES) " == *" $m "* ]]; then selected+=("$line"); fi
  done
  recap
  chosen=$("$GUM" choose --no-limit --no-show-help --header "What should it do? One or several modules (space to pick, enter to go on)" \
    --selected "$(IFS=,; echo "${selected[*]}")" "${items[@]}")
  answers[ALICE_MODULES]=$(echo "$chosen" | awk '{print $1}' | xargs)
  local ALICE_MODULES=${answers[ALICE_MODULES]} pick
  # The languages of the pinned OCR image.
  if has ocr; then
    local -A code=([English]=eng [French]=fra [German]=deu [Italian]=ita [Spanish]=spa [Japanese]=jpn)
    selected=()
    for pick in English French German Italian Spanish Japanese; do
      [[ "+$(value ALICE_OCR_LANGUAGES)+" == *"+${code[$pick]}+"* ]] && selected+=("$pick")
    done
    while :; do
      recap
      ui_note "Not in the list? The OCR image holds only these: add your language's Tesseract package to modules/ocr."
      chosen=$("$GUM" choose --no-limit --no-show-help --header "Languages of your documents and photos: one or several (space to pick, enter to go on)" \
        --selected "$(IFS=,; echo "${selected[*]}")" English French German Italian Spanish Japanese)
      [ -n "$chosen" ] && break
    done
    answers[ALICE_OCR_LANGUAGES]=$(for pick in $chosen; do echo "${code[$pick]}"; done | paste -sd+ -)
  fi
  if has stt || has tts; then
    recap
    answers[ALICE_STT_LANGUAGE]=$("$GUM" choose --header "Language people speak to it" --selected "$(value ALICE_STT_LANGUAGE)" \
      English French German Italian Spanish Portuguese Japanese)
    answers[ALICE_TTS_LANGUAGE]=${answers[ALICE_STT_LANGUAGE]}
  fi
}

# Detected from the machine when it is set there; any zone can be searched by typing.
ask_timezone() {
  local tz zones
  tz=$(value ALICE_TIMEZONE)
  if [[ $tz == UTC || $tz == Etc/UTC ]]; then tz=$(timedatectl show -p Timezone --value 2>/dev/null || echo UTC); fi
  zones=$( (echo "$tz"; timedatectl list-timezones 2>/dev/null) | awk '!seen[$0]++')
  recap
  answers[ALICE_TIMEZONE]=$(echo "$zones" | "$GUM" filter --header "Time zone of this installation (type to search, e.g. Berlin; enter to choose)" \
    --placeholder "type to search")
  [ -n "${answers[ALICE_TIMEZONE]}" ] || answers[ALICE_TIMEZONE]=$tz
}

# Advisory only. Model sizes come from where they are published; the other figures were measured on a test install.
fit_check() {
  local ALICE_MODULES people need=1 dl=0 m f url size pool label free dir sizes=() ctx tags largest together others
  ALICE_MODULES=$(value ALICE_MODULES)
  people=$(value ALICE_WORKSPACE_USERS | wc -w)
  gb() { awk -v b="$1" 'BEGIN { printf "%.1f", b / 1e9 }'; }
  add() { need=$(awk -v a="$need" -v b="$1" 'BEGIN { print a + b }'); }  # GB
  model_file() {  # URL MODULE
    size=$({ curl -sIL -m 15 "$1" || true; } | awk 'tolower($1) == "content-length:" { n = $2 } END { print n + 0 }' | tr -d '\r')
    add "$(gb "$size")"
    [ -s "$(value ALICE_DATA_DIR)/$2/models/$(basename "$1")" ] || dl=$((dl + size))
  }
  # Measured with GTT per process: decision model file + 4.2 GB, speech-to-text and images about their files.
  if has decision; then model_file "$DECISION_MODEL_URL" decision; add 4.5; fi
  if has images; then for url in "$IMAGES_DIFFUSION_URL" "$IMAGES_TEXT_ENCODER_URL" "$IMAGES_VAE_URL"; do model_file "$url" images; done; fi
  if has stt; then for url in "$STT_MODEL_URL" "$STT_ENCODER_URL"; do model_file "$url" stt; done; fi
  for m in tts:2 ocr:1 n8n:0.6 home-assistant:0.6 ntfy:0.1; do if has "${m%%:*}"; then add "${m#*:}"; fi; done
  if has workspace; then add "$(awk -v n="$people" 'BEGIN { print 0.12 * (n > 0 ? n : 1) }')"; fi
  # The embedding model of the document library.
  add 1
  # Context grows with its length: gemma4:26b measured 13.6 GB above its file at 262144 tokens.
  ctx=$(awk -v c="$(value ALICE_OLLAMA_CONTEXT_LENGTH)" 'BEGIN { printf "%.1f", (c > 0 ? c : 65536) / 262144 * 13.6 }')
  tags=$(curl -s -m 5 "http://127.0.0.1:$(value ALICE_OLLAMA_URL | sed 's/.*://')/api/tags" 2>/dev/null || true)
  for f in $(ALICE_PRESETS=$(value ALICE_PRESETS) preset_models); do
    size=$(echo "$tags" |
      python3 -I -B -c 'import json, sys; print(next((m["size"] for m in json.load(sys.stdin)["models"] if m["name"] == sys.argv[1]), 0))' "$f" 2>/dev/null || echo 0)
    if [ "${size:-0}" -eq 0 ] && [[ $f == hf.co/* ]]; then
      f=${f#hf.co/}
      size=$(curl -s -m 15 "https://huggingface.co/api/models/${f%%:*}/tree/main?recursive=1" |
        python3 -I -B -c 'import json, sys; q = sys.argv[1].lower(); print(sum(e.get("size", 0) for e in json.load(sys.stdin)
          if e["path"].lower().endswith(".gguf") and q in e["path"].lower() and "mmproj" not in e["path"].lower()))' \
        "${f#*:}" 2>/dev/null || echo 0)
      dl=$((dl + size))
    elif [ "${size:-0}" -eq 0 ]; then
      size=$(curl -s -m 15 -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
        "https://registry.ollama.ai/v2/library/${f%%:*}/manifests/${f#*:}" |
        python3 -I -B -c 'import json, sys; print(sum(l["size"] for l in json.load(sys.stdin)["layers"]))' 2>/dev/null || echo 0)
      dl=$((dl + size))
    fi
    sizes+=("${size:-0}")
  done
  others=$(awk -v a="$need" 'BEGIN { printf "%.0f", a }')
  # Ollama unloads one chat model to load another: only the largest must fit beside the modules.
  largest=$(printf '%s\n' "${sizes[@]}" | sort -rn | head -n 1 | awk -v c="$ctx" '{ printf "%.0f", $1 / 1e9 + c }')
  together=$(printf '%s\n' "${sizes[@]}" | sort -rn | head -n "$(value ALICE_OLLAMA_MAX_LOADED_MODELS)" |
    awk -v c="$ctx" '{ a += $1 / 1e9 + c } END { printf "%.0f", a }')
  need=$((others + largest))
  if command -v nvidia-smi >/dev/null; then
    pool=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | awk '{ s += $1 } END { printf "%.0f", s / 1024 }')
    label="GPU memory"
  else
    pool=$(awk '/MemTotal/ { printf "%.0f", $2 / 1048576 }' /proc/meminfo)
    label="memory"
  fi
  ui_say "Will it fit?"
  if [ "$need" -le $((pool * 8 / 10)) ]; then ui_ok "Memory: about $need of $pool GB of $label, for these modules and models"
  elif [ "$need" -le "$pool" ]; then ui_warn "Tight memory: about $need of $pool GB of $label; other programs may run short"
  else ui_tag 196 "NO FIT" "Memory: about $need GB needed, $pool GB of $label; leave a module or a model out"; fi
  ui_note "       largest chat model, with its context: $largest GB; modules (decision model, OCR, workspaces…): $others GB."
  if [ $((others + together)) -gt "$pool" ]; then
    ui_note "       Its $(value ALICE_OLLAMA_MAX_LOADED_MODELS) largest chat models do not fit at once: switching between them reloads one."
  fi
  if printf '%s\n' "${sizes[@]}" | grep -x 0 >/dev/null; then ui_note "       A model whose size could not be read is not counted."; fi
  dir=$(value ALICE_DATA_DIR)
  while [ ! -d "$dir" ]; do dir=$(dirname "$dir"); done
  free=$(df -B1 --output=avail "$dir" | tail -1)
  dl=$((dl + 15000000000))
  if [ "$dl" -lt "$free" ]; then ui_ok "Disk: about $(gb "$dl") GB to download, $(gb "$free") GB free"
  else ui_tag 196 "NO FIT" "Disk: about $(gb "$dl") GB to download, only $(gb "$free") GB free in $dir"; fi
  if [ "$BACKEND" = cpu ]; then
    for m in images stt tts; do if has "$m"; then ui_warn "No GPU: $m will be very slow"; fi; done
  fi
  if has workspace && ! command -v runsc >/dev/null; then
    ui_tag 196 "NO FIT" "The workspaces need gVisor, which is not installed (gvisor.dev/docs/user_guide/install)"
  fi
}

ask_people() {
  local me="Just me (the administrator account)" file="People from a file (one line each: name, e-mail)"
  local type="I will type them now" choice
  choice=$("$GUM" choose --header "Who will use it?" "$me" "$file" "$type")
  PEOPLE_FILE=/dev/null
  case "$choice" in
    "$file")
      while :; do
        PEOPLE_FILE=$(ui_ask "Path of the people file (from the harness folder, or a full path)" "")
        [ -f "$PEOPLE_FILE" ] && break
        ui_warn "No file at '$PEOPLE_FILE'."
      done
      ;;
    "$type")
      PEOPLE_FILE=$(mktemp)
      PEOPLE_TYPED=$PEOPLE_FILE UI_TMP=$PEOPLE_FILE
      "$GUM" write --header "One person per line: name, e-mail (add \", admin\" for an administrator)" \
        --placeholder "Jane Roe, jane@example.com" > "$PEOPLE_FILE"
      ;;
  esac
}

EGRESS_STEP="Building the egress proxy|bash security/egress/build.sh && bash security/egress/run.sh"

# Steps run in a child bash, hence the export -f below.
# A module that only runs a published image has no build.sh.
module_up() {
  local dir
  dir=$(module_dir "$1")
  { [ ! -f "$dir/build.sh" ] || bash "$dir/build.sh"; } && bash "$dir/run.sh"
}

clear_old() {
  set -eo pipefail
  load_settings
  local c m
  # Only containers of the harness's own modules: anything else under the prefix is not ours to remove.
  for c in $(docker ps -a --format '{{.Names}}' | grep "^${ALICE_PREFIX}-" || true); do
    for m in "$ALICE_ROOT"/modules/*/; do
      m=$(basename "$m")
      if ! has "$m" && [[ $c == "$ALICE_PREFIX-$m" || $c == "$ALICE_PREFIX-$m-"* ]]; then
        docker rm -f "$c"
        echo "removed $c, its module is no longer enabled"
      fi
    done
  done
}

# What change_modules compares: the settings asked along with the modules.
module_settings() {
  case $1 in
    ocr) value ALICE_OCR_LANGUAGES ;;
    stt) value ALICE_STT_LANGUAGE ;;
    tts) value ALICE_TTS_LANGUAGE ;;
  esac
}

# Modules already running, with the same settings and time zone, are left as they are. Running is read from the
# containers: machine.env may list a module that never started.
change_modules() {
  local m keep=() zone running
  local -A was=()
  zone=$(value ALICE_TIMEZONE)
  running=$(docker ps --format '{{.Names}}')
  for m in $(value ALICE_MODULES); do
    grep -qE "^$(value ALICE_PREFIX)-$m(-|$)" <<< "$running" && was[$m]=$(module_settings "$m")
  done
  ask_modules
  fit_check
  ui_confirm "Go on?" || exit 0
  save_settings
  if [ "$zone" = "$(value ALICE_TIMEZONE)" ]; then
    for m in "${!was[@]}"; do [ "${was[$m]}" != "$(module_settings "$m")" ] || keep+=("$m"); done
  fi
  KEEP_RUNNING="${keep[*]}" deploy
}

# Workspaces can only be granted once the accounts exist, hence the second Open WebUI start.
add_people() {
  set -eo pipefail
  load_settings
  install -d -m 700 "$ALICE_DATA_DIR/accounts"
  local out everyone admin password
  admin=$(secret WEBUI_ADMIN_EMAIL)
  password=$(secret WEBUI_ADMIN_PASSWORD)
  out=$(ALICE_TEST_URL="http://${ALICE_NET_CORE_SUBNET%.0/24}.2:8080" ALICE_TEST_ADMIN_EMAIL=$admin ALICE_TEST_ADMIN_PASSWORD=$password \
    python3 -I -B core/open-webui/people.py "$1" "$ALICE_DATA_DIR/accounts/new-accounts.csv") || { echo "$out"; return 1; }
  echo "$out" | head -1
  everyone=$( (echo "$admin"; echo "$out" | tail -n +2; echo "${ALICE_WORKSPACE_USERS:-}") | tr ' ' '\n' |
    tr '[:upper:]' '[:lower:]' | sed '/^$/d' | sort -u | xargs)
  sed -i "s|^ALICE_WORKSPACE_USERS=.*|ALICE_WORKSPACE_USERS=\"$everyone\"|" machine.env
  if has workspace; then bash modules/workspace/run.sh && bash core/open-webui/start.sh; fi
}
export ALICE_ROOT
export -f load_settings secret name module_dir has die info clear_old add_people module_up

deploy() {
  load_settings
  check_secrets
  local gone built=()
  gone=$(for m in $ALICE_MODULES; do [ -f "$(module_dir "$m")/run.sh" ] || echo "$m"; done | xargs)
  if [ -n "$gone" ]; then
    ui_fail "These modules no longer exist: $gone"
    ui_note "Choose the modules again: sudo ./install.sh modules"
    exit 1
  fi
  local steps=("Preparing the networks|bash security/networks.sh" "Raising the firewall|bash security/firewall.sh"
    "$EGRESS_STEP" "Setting up Ollama|bash core/ollama/setup.sh" "Tidying up|clear_old")
  # A change of modules leaves the networks, firewall, proxy and Ollama as they are; n8n's sites live in the proxy.
  if [ -n "${KEEP_RUNNING:-}" ]; then
    steps=("Tidying up|clear_old")
    if has n8n && [[ " $KEEP_RUNNING " != *" n8n "* ]]; then steps+=("$EGRESS_STEP"); fi
  fi
  for m in $ALICE_MODULES; do
    [[ " ${KEEP_RUNNING:-} " != *" $m "* ]] || continue
    steps+=("Building $m|module_up $m")
    built+=("$m")
  done
  steps+=("Starting Open WebUI|bash core/open-webui/start.sh")
  if has workspace && [ -z "${ALICE_WORKSPACE_USERS:-}" ]; then PEOPLE_FILE=${PEOPLE_FILE:-/dev/null}; fi
  if [ -n "${PEOPLE_FILE:-}" ]; then steps+=("Welcoming the people|add_people '$PEOPLE_FILE'"); fi
  steps+=("Setting the health alerts|bash doctor/units.sh")
  ui_note "This takes a while the first time (images and models to download): time for a coffee."
  ui_progress "${steps[@]}"
  forget_people
  # After a change of modules, the ones left running were already checked.
  if [ -n "${KEEP_RUNNING:-}" ]; then check "${built[@]}" security; else check; fi
}

welcome_people() {
  load_settings
  check_secrets
  ui_progress "Welcoming the people|add_people '$PEOPLE_FILE'"
  forget_people
  if [ -s "$ALICE_DATA_DIR/accounts/new-accounts.csv" ]; then
    ui_card "New accounts, with their temporary passwords:" "$ALICE_DATA_DIR/accounts/new-accounts.csv (root only)"
  fi
  check open-webui workspace
}

forget_people() { if [ -n "${PEOPLE_TYPED:-}" ]; then rm -f "$PEOPLE_TYPED"; fi; }

check() {
  load_settings
  local report=$ALICE_DATA_DIR/doctor/last.txt passed failed
  rm -f "$report"
  # The bar advances with each test that ends.
  local labels=$*
  if [ -z "$labels" ]; then
    labels="open-webui ollama soul $ALICE_MODULES security egress"
    if has decision && has workspace; then labels+=" approvals"; fi
  fi
  UI_STEP_TOTAL=$(echo "$labels" | wc -w) UI_STEP_DONE=': (all checks passed|[0-9]+ check\(s\) failed)$' \
    ui_progress "Checking everything|bash doctor/doctor.sh $* || true"
  if ! grep -q '^doctor: ' "$report" 2>/dev/null; then
    ui_fail "The checks could not run"
    tail -n 10 "$UI_LOG" | "$GUM" style --foreground "$UI_SOFT" --margin "0 2"
    ui_note "The whole log: $UI_LOG"
    return
  fi
  passed=$(grep -c '^  PASS' "$report" || true)
  failed=$(grep -c '^  FAIL' "$report" || true)
  if grep -q '^doctor: everything passed' "$report"; then
    ui_ok "$passed checks, all passed"
    return
  fi
  if [ "$failed" -gt 0 ]; then
    ui_fail "$failed of $((passed + failed)) checks failed:"
    grep '^  FAIL' "$report" | sed 's/^  FAIL  /  /' | "$GUM" style --foreground 214
  fi
  ui_fail "Tests with a failure or stopped early: $(sed -n 's/^doctor: failed: //p' "$report")"
  ui_note "Full report: $report"
}

final_card() {
  load_settings
  local net=${ALICE_NET_CORE_SUBNET%.0/24} lines=()
  lines+=("Open WebUI       ${ALICE_WEBUI_URL:-http://$net.2:8080  (reach it through your tunnel or reverse proxy)}")
  if has home-assistant; then lines+=("Home Assistant   http://$net.90:8123"); fi
  if has n8n; then lines+=("n8n              ${ALICE_N8N_URL:-http://$net.70:5678}"); fi
  if has ntfy; then lines+=("ntfy             ${ALICE_NTFY_URL:-http://$net.80:8080}"); fi
  lines+=("" "Administrator    $(secret WEBUI_ADMIN_EMAIL)")
  if [ -s "$ALICE_DATA_DIR/accounts/new-accounts.csv" ]; then
    lines+=("New accounts     $ALICE_DATA_DIR/accounts/new-accounts.csv" "                 (temporary passwords, root only)")
  fi
  lines+=("" "To change something later: sudo ./install.sh (modules, models, soul, people, alerts)," \
    "or edit machine.env, then sudo ./install.sh update.")
  ui_card "Ready." "" "${lines[@]}"
  offer_alerts
}

offer_alerts() {
  load_settings
  if has ntfy && [ -z "${ALICE_ALERT_TOPIC:-}" ] && ui_confirm "The phone alerts are not set up. Set them up now?"; then alerts; fi
}

alerts() {
  load_settings
  local topic user password container url
  if ! has ntfy; then
    ui_warn "The phone alerts go through the ntfy module: add it first (sudo ./install.sh modules)."
    return
  fi
  container=$(name ntfy)
  topic=$(ui_ask "Name of the alert topic" "${ALICE_ALERT_TOPIC:-$ALICE_PREFIX-alerts}")
  user=$(ui_ask "Your ntfy user name, to sign in from the phone" "owner")
  password=$(ask_password "Its password (8 characters or more)" 8)
  url=$(ui_ask "Public address of ntfy, through your reverse proxy or tunnel (empty if none yet)" "${ALICE_NTFY_URL:-}")
  if ! NTFY_PASSWORD=$password docker exec -e NTFY_PASSWORD "$container" ntfy user add "$user" >>"$UI_LOG" 2>&1; then
    NTFY_PASSWORD=$password docker exec -e NTFY_PASSWORD "$container" ntfy user change-pass "$user" >>"$UI_LOG" 2>&1 ||
      { ui_fail "Could not create the ntfy account $user (see $UI_LOG)"; return; }
  fi
  docker exec "$container" ntfy access "$user" "$topic" read-only >>"$UI_LOG" 2>&1 ||
    { ui_fail "Could not give $user the topic $topic (see $UI_LOG)"; return; }
  sed -i -e "s|^ALICE_ALERT_TOPIC=.*|ALICE_ALERT_TOPIC=\"$topic\"|" -e "s|^ALICE_NTFY_URL=.*|ALICE_NTFY_URL=\"$url\"|" machine.env
  ALICE_NTFY_URL=$url
  ui_wait "Setting the health alerts" bash doctor/units.sh || { ui_fail "Could not set the health alerts (see $UI_LOG)"; return; }
  if [ "${url:-http://${ALICE_NET_CORE_SUBNET%.0/24}.80}" != "$(grep -o 'base-url: .*' "$ALICE_DATA_DIR/ntfy/server.yml" 2>/dev/null | cut -d' ' -f2- | tr -d '"')" ]; then
    ui_wait "Giving ntfy its address" bash modules/ntfy/run.sh || ui_warn "ntfy did not restart with its new address (see $UI_LOG)"
  fi
  if printf 'header = "Authorization: Bearer %s"\n' "$(cat "$ALICE_DATA_DIR/ntfy/harness.token")" |
    curl -sf -m 15 -K - -H "Title: Alerts are ready" --data-binary "You will hear from your assistant only when something breaks." \
      "http://${ALICE_NET_CORE_SUBNET%.0/24}.80:8080/$topic" >/dev/null; then
    ui_ok "Test alert sent"
  else
    ui_warn "The test alert could not be sent (see $UI_LOG)"
  fi
  ui_card "On the phone: install the ntfy app, add the server ${ALICE_NTFY_URL:-(your ntfy address)}," \
    "sign in as $user, and subscribe to $topic."
}

# Ask everything before touching anything.
uninstall() {
  load_settings
  ui_confirm --default=false "Remove every container, network and firewall rule of '$ALICE_PREFIX'?" || exit 0
  local data=no models=no kept="Ollama, the secrets and machine.env were kept." steps
  if ui_confirm --default=false "Also delete the data in $ALICE_DATA_DIR (accounts, chats, files)?"; then
    data=yes
    if ui_confirm --default=false "And the downloaded model files (tens of GB, long to download again)?"; then models=yes; fi
  fi
  steps=("Removing the containers|remove_containers" "Removing the networks|remove_networks"
    "Removing the firewall rules|remove_rules" "Removing the health alerts|remove_units")
  if [ "$data" = yes ]; then
    [[ $ALICE_DATA_DIR == /?*/?* ]] || die "refusing to delete '$ALICE_DATA_DIR': not a data folder"
    if [ "$models" = yes ]; then
      steps+=("Deleting the data|rm -rf --one-file-system '$ALICE_DATA_DIR'")
    else
      steps+=("Deleting the data, keeping the models|remove_data")
      kept="Ollama, the model files, the secrets and machine.env were kept."
    fi
  fi
  ui_progress "${steps[@]}"
  ui_ok "Uninstalled. $kept"
}

remove_containers() { docker ps -a --format '{{.Names}}' | { grep "^${ALICE_PREFIX}-" || true; } | xargs -r docker rm -f; }
remove_networks() { docker network rm "$ALICE_NET_CORE" "$ALICE_NET_EGRESS" "$ALICE_NET_WORKSPACE" || true; }
remove_rules() {
  local n
  while n=$(ufw status numbered | grep -E "# alice-harness-$ALICE_PREFIX$" | head -1 | sed -n 's/^\[ *\([0-9]*\)\].*/\1/p'); [ -n "$n" ]; do
    ufw --force delete "$n"
  done
}
remove_units() {
  systemctl disable --now "$ALICE_PREFIX-health.timer" "$ALICE_PREFIX-unlock-alert.service" "$ALICE_PREFIX-backup.timer" || true
  # The backup repository and its key stay.
  rm -f /etc/systemd/system/"$ALICE_PREFIX"-{health.service,health.timer,unlock-alert.service,backup.service,backup.timer}
  # Only ours in native mode.
  if [ "$ALICE_OLLAMA_MODE" = native ]; then rm -f /etc/systemd/system/ollama.service.d/{zz-,}alice-harness.conf; fi
  systemctl daemon-reload
}
# A module keeps its downloaded files in models/ (model/ for tts).
remove_data() {
  local d
  for d in "$ALICE_DATA_DIR"/*/; do
    if [ -d "$d/models" ] || [ -d "$d/model" ]; then
      find "$d" -mindepth 1 -maxdepth 1 ! -name models ! -name model -exec rm -rf --one-file-system {} +
    else
      rm -rf --one-file-system "$d"
    fi
  done
  find "$ALICE_DATA_DIR" -maxdepth 1 -type f -delete
}
export -f remove_containers remove_networks remove_rules remove_units remove_data

update_one() {
  load_settings
  check_secrets
  local module=${1:-}
  local enabled
  read -ra enabled <<< "$ALICE_MODULES"
  [ -n "$module" ] || module=$("$GUM" choose --header "Which one?" open-webui "${enabled[@]}")
  if [ "$module" = open-webui ]; then
    local steps=("Restarting Open WebUI|bash core/open-webui/start.sh")
    # Workspaces are granted by account and group ids, which a restored database does not share.
    if has workspace; then steps+=("Connecting the workspaces|bash modules/workspace/run.sh && bash core/open-webui/start.sh"); fi
    ui_progress "${steps[@]}"
    check open-webui soul approvals
    return
  fi
  has "$module" || die "'$module' is not an enabled module"
  local steps=("Building $module|module_up $module")
  # n8n's list of sites lives in the egress proxy.
  if [ "$module" = n8n ]; then steps=("$EGRESS_STEP" "${steps[@]}"); fi
  if [ -f "$(module_dir "$module")/openwebui.conf" ] || [ -f "$ALICE_DATA_DIR/$module/openwebui.conf" ]; then
    steps+=("Restarting Open WebUI|bash core/open-webui/start.sh")
  fi
  ui_progress "${steps[@]}"
  check "$module" security
}

change_assistant() {
  ask_assistant
  fit_check
  ui_confirm "Go on?" || exit 0
  save_settings
  load_settings
  check_secrets
  ui_progress "Raising the firewall|bash security/firewall.sh" "Setting up Ollama|bash core/ollama/setup.sh" \
    "Restarting Open WebUI|bash core/open-webui/start.sh"
  check ollama open-webui soul approvals
}

status_card() {
  load_settings
  local report=$ALICE_DATA_DIR/doctor/last.txt health="never checked"
  if [ -f "$report" ]; then
    if grep -q '^doctor: everything passed' "$report"; then health="all passed"
    else health="$(grep -c '^  FAIL' "$report" || true) check(s) failing"; fi
    health="$health, $(date -r "$report" '+%Y-%m-%d %H:%M')"
  fi
  [ -z "$PARTIAL" ] || health="not finished: choose \"Update everything\""
  ui_card "Installed · $(echo "$ALICE_MODULES" | wc -w) modules: $ALICE_MODULES" "Health: $health"
}

# Never reuse names or subnets already taken on this host.
# Linux limits interface names to 15 characters: br-<name>-core leaves 7 for the name.
ask_place() {
  local prefix taken subnet used dir key
  prefix=$(value ALICE_PREFIX)
  while :; do
    prefix=$(ui_ask "Name of this installation (up to 7 lowercase letters or digits)" "$prefix")
    if ! [[ $prefix =~ ^[a-z][a-z0-9]{0,6}$ ]]; then
      ui_warn "Up to 7 lowercase letters or digits, starting with a letter."
      prefix=$(echo "$prefix" | tr -cd 'a-z0-9' | cut -c1-7)
      continue
    fi
    taken=$(docker ps -a --format '{{.Names}}' | grep -c "^$prefix-" || true)
    [ "$taken" -eq 0 ] && break
    ui_warn "$taken containers here already start with '$prefix-' and are not from this installation."
    prefix="${prefix:0:6}2"
  done
  answers[ALICE_PREFIX]=$prefix
  answers[ALICE_NET_CORE]=$prefix-core
  answers[ALICE_NET_EGRESS]=$prefix-egress
  answers[ALICE_NET_WORKSPACE]=$prefix-workspace
  read -ra used <<< "$(docker network ls -q | xargs -r docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' | xargs) \
$(ip -4 route show | awk '$1 ~ /\// { print $1 }' | xargs)"
  for key in ALICE_NET_CORE_SUBNET ALICE_NET_EGRESS_SUBNET ALICE_NET_WORKSPACE_SUBNET; do
    subnet=$(value "$key")
    while python3 -I -B -c 'import ipaddress as i, sys; n = i.ip_network(sys.argv[1])
sys.exit(0 if any(n.overlaps(i.ip_network(u, strict=False)) for u in sys.argv[2:]) else 1)' \
      "$subnet" "${used[@]}"; do
      subnet=$(echo "$subnet" | awk -F. '{printf "%s.%d.%s.%s", $1, $2 + 2, $3, $4}')
    done
    answers[$key]=$subnet
    used+=("$subnet")
  done
  dir=$(value ALICE_DATA_DIR)
  if [ "$prefix" != "$(current ALICE_PREFIX)" ]; then
    dir=/srv/$prefix-harness/data
  fi
  while :; do
    dir=$(ui_ask "Folder for its data (models, accounts, chats)" "$dir")
    [[ $dir == /?*/?* || $dir == /srv/?* ]] && break
    ui_warn "A full path, such as /srv/$prefix-harness/data."
  done
  answers[ALICE_DATA_DIR]=$dir
}

# Fail before deploying rather than halfway through.
check_secrets() {
  local s missing=()
  for s in WEBUI_SECRET_KEY WEBUI_ADMIN_EMAIL WEBUI_ADMIN_PASSWORD $(has n8n && echo N8N_ENCRYPTION_KEY) \
    $([ -z "${ALICE_OIDC_PROVIDER_URL:-}" ] || echo OAUTH_CLIENT_ID OAUTH_CLIENT_SECRET); do
    [ -n "$(secret "$s" 2>>"$UI_LOG" </dev/null)" ] || missing+=("$s")
  done
  if [ ${#missing[@]} -gt 0 ]; then
    ui_fail "The secret store ($ALICE_SECRET_STORE) does not give: ${missing[*]}"
    ui_note "What to put there, and how: security/SECRETS.md"
    exit 1
  fi
  ui_ok "The secrets are in place"
}

fresh_install() {
  ui_card "Nothing is installed here yet." "" "Set up your assistant"
  [ "$("$GUM" choose --header "What do you want to do?" "Install A.L.I.C.E. Harness" "Quit" || true)" = "Install A.L.I.C.E. Harness" ] || exit 0
  recap; ask_place
  recap; ask_secrets
  ask_assistant
  ask_modules
  ask_timezone
  recap; fit_check
  ask_people
  answers[ALICE_BACKEND]=$BACKEND
  recap
  ui_confirm "Install now?" || exit 0
  save_settings
  load_settings
  if [ "$ALICE_SECRET_STORE" = file ]; then
    ALICE_ADMIN_EMAIL=${answers[ALICE_ADMIN_EMAIL_NEW]:-} ALICE_ADMIN_PASSWORD=${answers[ALICE_ADMIN_PASSWORD_NEW]:-} \
      bash security/secrets.sh init </dev/null >>"$UI_LOG" 2>&1 || { ui_fail "Could not write the secrets file"; ui_note "See $UI_LOG"; exit 1; }
  fi
  deploy
  final_card
}

ui_logo
discover
installed() {
  [ -n "$INSTALLED" ] && return 0
  ui_fail "A.L.I.C.E. Harness is not installed here yet"
  ui_note "Install it first: sudo ./install.sh"
  exit 1
}
# Settings added to the template since the installation get their defaults.
if [ -n "$INSTALLED" ]; then save_settings; fi
command=${1:-}
if [ -z "$command" ]; then
  if [ -z "$INSTALLED" ]; then fresh_install; exit 0; fi
  status_card
  case "$("$GUM" filter --header "What do you want to do?" --placeholder "type to filter" \
    "Update everything to the pinned versions" "Add or remove modules" "Update one module" "Add people" \
    "Personalise the assistant" "Set up the phone alerts" "Run the checks" "Uninstall" "Quit")" in
    Update\ everything*) command=update ;;
    Add\ or\ remove*) command=modules ;;
    Update\ one*) command=module ;;
    Add\ people) command=people ;;
    Personalise*) command=assistant ;;
    Set\ up*) command=alerts ;;
    Run\ the\ checks) command=check ;;
    Uninstall) command=uninstall ;;
    *) exit 0 ;;
  esac
fi
case "$command" in
  update) installed; deploy; final_card ;;
  module) installed; update_one "${2:-}" ;;
  modules) installed; change_modules ;;
  people) installed; ask_people; welcome_people ;;
  assistant) installed; change_assistant ;;
  alerts) installed; alerts ;;
  check) installed; check "${@:2}"; offer_alerts ;;
  uninstall) [ -f machine.env ] || die "nothing to uninstall: machine.env is missing"; uninstall ;;
  *) die "unknown command '$command' (see the first line of install.sh)" ;;
esac
