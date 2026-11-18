# gum-based UI for the installer and the doctor. Step output only goes to $UI_LOG.

UI_PHRASES=(
  "sniffing the GPU" "counting gigabytes" "politely asking Docker" "untangling cables" "warming up the tensors"
  "convincing FLUX to behave" "teaching the parrot new words" "herding containers" "polishing the gVisor walls"
  "negotiating with the firewall" "feeding the decision model" "reticulating splines" "brewing coffee for Ollama"
  "aligning the bits" "asking the proxy nicely" "dusting off the workspaces" "tuning the voice" "folding the logs"
  "asking the GPU for a dance" "untying knots in the YAML" "persuading packets to queue nicely" "feeding the hamsters"
  "reading the manual, for once" "teaching Ollama some manners" "checking under the sofa for lost bytes"
  "giving the containers a pep talk" "sharpening the tokens" "counting sheep in binary" "waking the models gently"
  "ironing the configuration" "bribing the download mirrors" "stacking layers with care" "letting the electrons settle"
  "warming up the cache" "humming while it compiles" "double-checking the checksums" "lining up the subnets"
  "rehearsing the first hello" "whispering to the decision model" "making the bed for the models"
  "unpacking tiny suitcases" "measuring twice, cutting once" "pouring a second coffee" "lining up the ducks"
  "tidying the toolbox" "proofreading the logs" "politely ignoring the progress bar" "watering the server plants"
  "finding the right key on the ring" "naming the containers" "rolling the dice, deterministically"
  "teaching the firewall to say no" "stretching before the big download" "putting the kettle on"
  "convincing the bits to line up" "giving the soul a final polish" "checking the oil and the tyres"
)
UI_FRAMES=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
UI_PID='' UI_TMP=''

# Kill the running step's process group and restore the cursor.
ui_cleanup() {
  if [ -n "$UI_PID" ]; then kill -TERM -- "-$UI_PID" 2>/dev/null || true; fi
  if [ -n "$UI_TMP" ]; then rm -f "$UI_TMP"; fi
  if [ -t 0 ]; then stty echo; fi
  printf '\033[?25h'
}

ui_init() {
  local arch dir
  case "$(uname -m)" in
    x86_64) arch=x86_64 ;;
    aarch64 | arm64) arch=arm64 ;;
    *) die "no terminal interface for $(uname -m)" ;;
  esac
  dir=/usr/local/lib/alice-harness/gum-$GUM_VERSION
  if [ ! -x "$dir/gum" ]; then
    local sum=GUM_SHA256_$arch
    (fetch "https://github.com/charmbracelet/gum/releases/download/v$GUM_VERSION/gum_${GUM_VERSION}_Linux_$arch.tar.gz" \
      "${!sum}" "$dir/gum.tar.gz") >>"$UI_LOG" 2>&1 || die "could not download the terminal interface (gum), see $UI_LOG"
    tar -xzf "$dir/gum.tar.gz" -C "$dir" --strip-components 1 "gum_${GUM_VERSION}_Linux_$arch/gum" ||
      die "could not unpack the terminal interface (gum)"
  fi
  GUM=$dir/gum
  trap ui_cleanup EXIT
  trap 'exit 130' INT TERM
  # 256-colour codes
  UI_MAIN=45 UI_GOLD=220 UI_TEXT=195 UI_SOFT=110 UI_DIM=238
  export GUM_CHOOSE_CURSOR_FOREGROUND=$UI_MAIN GUM_CHOOSE_SELECTED_FOREGROUND=$UI_MAIN GUM_CHOOSE_HEADER_FOREGROUND=$UI_SOFT
  export GUM_FILTER_INDICATOR_FOREGROUND=$UI_MAIN GUM_FILTER_MATCH_FOREGROUND=$UI_GOLD GUM_FILTER_HEADER_FOREGROUND=$UI_SOFT
  export GUM_FILTER_PROMPT_FOREGROUND=$UI_MAIN GUM_INPUT_CURSOR_FOREGROUND=$UI_MAIN GUM_INPUT_HEADER_FOREGROUND=$UI_SOFT
  export GUM_INPUT_PROMPT_FOREGROUND=$UI_MAIN GUM_WRITE_HEADER_FOREGROUND=$UI_SOFT
  export GUM_CONFIRM_SELECTED_BACKGROUND=$UI_MAIN GUM_CONFIRM_SELECTED_FOREGROUND=16 GUM_SPIN_SPINNER_FOREGROUND=$UI_GOLD
  export GUM_CHOOSE_HEIGHT=12 GUM_FILTER_HEIGHT=12 GUM_WRITE_HEIGHT=8
}

ui_logo() {
  local art=(
    " ██████        ██           ██        ██████       ███████"
    "██    ██       ██           ██       ██            ██     "
    "████████       ██           ██       ██            █████  "
    "██    ██       ██           ██       ██            ██     "
    "██    ██  ██   ███████  ██  ██  ██    ██████  ██   ███████  ██"
  )
  if [ ! -t 1 ]; then printf '%s\n' "${art[@]}"; return; fi
  clear
  local cells=() r c line batch=0
  for r in "${!art[@]}"; do
    line=${art[$r]}
    for ((c = 0; c < ${#line}; c++)); do [ "${line:$c:1}" != " " ] && cells+=("$((r + 2)) $((c + 4))"); done
  done
  local pause
  pause=$(awk -v n="${#cells[@]}" 'BEGIN { printf "%.3f", 1.8 * 3 / n }')
  printf '\033[?25l\033[38;5;%sm' "$UI_MAIN"
  while read -r r c; do
    printf '\033[%d;%dH█' "$r" "$c"
    if ((++batch % 3 == 0)); then sleep "$pause"; fi
  done < <(printf '%s\n' "${cells[@]}" | shuf)
  printf '\033[0m\033[8;4H\033[38;5;%smA.L.I.C.E. Harness · your own assistant, on your own machine\033[0m\n\n\033[?25h' "$UI_SOFT"
}

ui_say() { "$GUM" style --foreground "$UI_TEXT" --bold "$@"; }
ui_note() { "$GUM" style --foreground "$UI_SOFT" --italic "$@"; }
ui_tag() { printf '\033[1;38;5;%sm[%s]\033[0m %s\n' "$1" "$2" "$3"; }
ui_ok() { ui_tag 42 OK "$*"; }
ui_warn() { ui_tag 214 WARN "$*"; }
ui_fail() { ui_tag 196 FAIL "$*"; }
ui_card() { "$GUM" style --border rounded --border-foreground "$UI_MAIN" --foreground "$UI_TEXT" --padding "1 2" --margin "1 0" "$@"; }
ui_ask() { "$GUM" input --prompt "› " --placeholder "$2" --value "$2" --header "$1"; }
ui_secret() { "$GUM" input --password --prompt "› " --header "$1"; }
ui_confirm() { "$GUM" confirm "$@"; }

# A wrapped line breaks the cursor-up redraw.
ui_cut() {
  local max=$(($(tput cols 2>/dev/null || echo 80) - 6))
  printf '%s' "${1:0:max}"
}

# Own process group so Ctrl-C can kill the whole step; no tty so nothing can prompt unseen. Typed keys are not
# echoed: a line feed would shift the redraw.
ui_start() {
  setsid -w bash -c "$1" </dev/null >>"$UI_LOG" 2>&1 &
  UI_PID=$!
  if [ -t 0 ]; then stty -echo; fi
}

ui_end() {
  local status=0
  wait "$UI_PID" || status=$?
  UI_PID=
  # Keys typed while the step ran were not shown; drop them so none answers the next question.
  if [ -t 0 ]; then
    while IFS= read -r -s -t 0.01 -n 1000 _; do :; done
    stty echo
  fi
  return "$status"
}

# ui_wait TITLE CMD...
ui_wait() {
  local title=$1 phrase tick=0
  shift
  phrase=${UI_PHRASES[RANDOM % ${#UI_PHRASES[@]}]}
  ui_start "$(printf '%q ' "$@")"
  printf '\033[?25l'
  while kill -0 "$UI_PID" 2>/dev/null; do
    printf '\r\033[38;5;%sm%s\033[0m \033[38;5;%sm%s\033[0m\033[K' "$UI_GOLD" "${UI_FRAMES[tick % 10]}" "$UI_TEXT" \
      "$(ui_cut "$title… ($phrase)")"
    sleep 0.1
    tick=$((tick + 1))
  done
  printf '\r\033[K\033[?25h'
  ui_end
}

# tr works on bytes and would cut a multi-byte character in half.
ui_repeat() { local s; printf -v s '%*s' "$2" ''; printf '%s' "${s// /$1}"; }

# Progress meters rewrite their line with \r: only the latest piece counts.
ui_last_line() { tail -c 4096 "$UI_LOG" 2>/dev/null | tr '\r\t' '\n ' | grep -a -v '^ *$' | tail -n 1 || true; }

# ui_progress "label|command"...   exits on the first failing step
# With UI_STEP_TOTAL and UI_STEP_DONE (a regex), a step also advances the bar each time its log gets a matching line.
ui_progress() {
  local total=$# i=0 step label cmd phrase tick width=34 done_w status frame shown='' last='' parts sub start percent
  parts=${UI_STEP_TOTAL:-1}
  printf '\033[?25l\n\n\n'
  for step in "$@"; do
    label=${step%%|*}
    cmd=${step#*|}
    start=$(stat -c %s "$UI_LOG")
    sub=0
    ui_start "$cmd"
    tick=0
    while kill -0 "$UI_PID" 2>/dev/null; do
      ((tick % 40 == 0)) && phrase=${UI_PHRASES[RANDOM % ${#UI_PHRASES[@]}]}
      if ((tick % 5 == 0)); then
        last=$(ui_cut "$(ui_last_line)")
        if [ -n "${UI_STEP_DONE:-}" ]; then
          sub=$(tail -c +"$((start + 1))" "$UI_LOG" | grep -cE "$UI_STEP_DONE" || true)
          ((sub < parts)) || sub=$((parts - 1))
        fi
      fi
      done_w=$((width * (i * parts + sub) / (total * parts)))
      percent=$((100 * (i * parts + sub) / (total * parts)))
      # Lines are overwritten in place and only when they change: clearing first makes the screen flicker.
      frame=$(printf '  \033[38;5;%sm%s\033[38;5;%sm%s\033[0m  %3d%%\033[K\n  \033[38;5;%sm%s\033[0m\033[K\n  \033[38;5;%sm└ %s\033[0m\033[K' \
        "$UI_MAIN" "$(ui_repeat █ "$done_w")" "$UI_DIM" "$(ui_repeat ░ "$((width - done_w))")" \
        "$percent" "$UI_TEXT" "$(ui_cut "$label  ($phrase)")" "$UI_DIM" "$last")
      if [ "$frame" != "$shown" ]; then printf '\033[3A\r%s\n' "$frame"; shown=$frame; fi
      sleep 0.1
      tick=$((tick + 1))
    done
    status=0
    ui_end || status=$?
    if [ "$status" -ne 0 ]; then
      printf '\033[3A\033[J\033[?25h'
      ui_fail "$label failed"
      tail -n 15 "$UI_LOG" | fold -w "$(($(tput cols 2>/dev/null || echo 80) - 4))" | tail -n 20 | "$GUM" style --foreground "$UI_SOFT" --margin "0 2"
      ui_note "The whole log: $UI_LOG"
      exit 1
    fi
    i=$((i + 1))
  done
  printf '\033[3A\033[J  \033[38;5;%sm%s\033[0m  100%%\n\033[?25h' "$UI_MAIN" "$(ui_repeat █ "$width")"
}
