#!/bin/bash
# Backend for the io.github.snouhaud.rclone-mounter Omarchy shell plugin.
# Non-interactive (except `unlock`): every command prints one JSON line.
#
# An encrypted rclone config is unlocked with the password stored in the
# Secret Service keyring under the attributes `service rclone key config`
# (store it with: secret-tool store --label="rclone config" service rclone key config).
#
#   rclone-mounts.sh status  <base> <excluded,csv> <readonly,csv>
#   rclone-mounts.sh mount   <base> <remote> <full|writes|read-only> <readonly,csv> <open:0|1>
#   rclone-mounts.sh unmount <base> <remote>
#   rclone-mounts.sh unlock
#   rclone-mounts.sh forget        # delete the stored password from the keyring
#
# Arguments arrive as argv from QML (never through a shell string) and are
# validated here before use.

# Keep the caller's locale for ui_lang before forcing a stable one for tools.
ORIG_LC_ALL="${LC_ALL:-}"
export LC_ALL=C.UTF-8
set -o pipefail

json_error() {
  jq -cn --arg code "$1" --arg detail "${2:-}" '{ok: false, error: $code, detail: ($detail | .[0:300])}'
  exit 0
}

command -v jq >/dev/null 2>&1 || { echo '{"ok":false,"error":"jqMissing"}'; exit 0; }

# --- Prerequisites ----------------------------------------------------------
have_rclone() { command -v rclone >/dev/null 2>&1; }
have_fuse() { command -v fusermount3 >/dev/null 2>&1 && [[ -c /dev/fuse ]]; }
have_secret_tool() { command -v secret-tool >/dev/null 2>&1; }
have_zenity() { command -v zenity >/dev/null 2>&1; }

# UI language for notifications and the password dialog: the Omarchy language
# when set, else the system locale, else English (same rule as Language.js).
ui_lang() {
  local file="${OMARCHY_LANGUAGE_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/language}"
  local code=""
  [[ -f $file ]] && code=$(head -n 1 "$file" | tr -d '[:space:]')
  [[ -n $code ]] || code="${ORIG_LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
  code="${code%%[._@-]*}"
  [[ $code =~ ^[a-zA-Z]{2,3}$ && $code != C ]] || code=en
  printf '%s' "${code,,}"
}

# msg <key> [args...]: a translated message (French or English).
msg() {
  local key="$1"; shift
  local fr=0
  [[ $(ui_lang) == fr ]] && fr=1
  case "$key" in
    mounted) ((fr)) && printf '%s monté sur %s (%s)' "$@" || printf 'Mounted %s at %s (%s)' "$@" ;;
    unmounted) ((fr)) && printf '%s démonté' "$@" || printf 'Unmounted %s' "$@" ;;
    password) ((fr)) && printf 'Mot de passe de la configuration rclone' || printf 'rclone configuration password' ;;
    forgotten) ((fr)) && printf 'Mot de passe rclone supprimé du trousseau' || printf 'rclone password removed from the keyring' ;;
  esac
}

# Desktop notification, skipped quietly when notify-send is not installed.
notify() {
  command -v notify-send >/dev/null 2>&1 && notify-send "rclone" "$1" 2>/dev/null
  return 0
}

# Sets CONFIG_PATH; succeeds when the rclone config file exists and is non-empty.
# Honors RCLONE_CONFIG through rclone itself.
have_config() {
  CONFIG_PATH=$(rclone config file 2>/dev/null | tail -n 1)
  [[ -n $CONFIG_PATH && -s $CONFIG_PATH ]]
}

require_rclone() { have_rclone || json_error rcloneMissing; }
require_fuse() { have_fuse || json_error fuseMissing; }
require_config() { have_config || json_error noConfig "$CONFIG_PATH"; }
require_secret_tool() { have_secret_tool || json_error secretToolMissing; }
require_zenity() { have_zenity || json_error zenityMissing; }

# Status reply when a prerequisite blocks listing remotes.
status_blocked() {
  printf '%s\n' "$@" | jq -cRs --arg base "$BASE" --arg config "${CONFIG_PATH:-}" \
    --argjson stored "$(keyring_stored_json)" \
    '{ok: true, locked: false, base: $base, configPath: $config, keyringStored: $stored,
      issues: (split("\n") | map(select(. != ""))), remotes: []}'
  exit 0
}

# "true" when a config password is stored in the keyring, else "false".
keyring_stored_json() {
  if have_secret_tool && [[ -n $(secret-tool lookup service rclone key config 2>/dev/null) ]]; then
    echo true
  else
    echo false
  fi
}

# Sets BASE (no subshell, so json_error really ends the script).
expand_base() {
  local base="${1:-$HOME/mnt}"
  [[ -z $base ]] && base="$HOME/mnt"
  [[ $base == "~" ]] && base="$HOME"
  [[ $base == "~/"* ]] && base="$HOME/${base#\~/}"
  [[ $base == /* ]] || json_error invalidBase "$base"
  BASE="${base%/}"
}

valid_remote() {
  [[ $1 =~ ^[A-Za-z0-9_][A-Za-z0-9_.@+-]{0,63}$ ]]
}

in_csv() {
  local needle="$1" csv="$2" item
  IFS=',' read -ra items <<<"$csv"
  for item in "${items[@]}"; do
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    [[ $item == "$needle" ]] && return 0
  done
  return 1
}

# Password: GNOME keyring only. Prompting happens in `unlock`, never in status.
load_password() {
  local p
  have_secret_tool || return 1
  p=$(secret-tool lookup service rclone key config 2>/dev/null)
  [[ -n $p ]] || return 1
  export RCLONE_CONFIG_PASS="$p"
}

list_remotes() {
  # Prints "name<TAB>type" lines.
  rclone listremotes --long --ask-password=false </dev/null 2>/dev/null | awk '{ n=$1; sub(/:$/, "", n); print n "\t" $2 }'
}

cmd_status() {
  local base excluded readonly_csv
  expand_base "$1"; base="$BASE"
  excluded="$2"
  readonly_csv="$3"

  local issues=()
  have_rclone || status_blocked rcloneMissing
  have_fuse || issues+=(fuseMissing)
  have_config || status_blocked "${issues[@]}" noConfig

  # A plain (unencrypted) config works without a password.
  load_password
  local listing
  if ! listing=$(list_remotes); then
    # Locked: no stored password, or a stored one that no longer works.
    # Unlocking needs a keyring client and a password dialog.
    local stored=false
    if [[ -n ${RCLONE_CONFIG_PASS:-} ]]; then
      stored=true
      issues+=(badPassword)
    fi
    have_secret_tool || issues+=(secretToolMissing)
    have_zenity || issues+=(zenityMissing)
    printf '%s\n' "${issues[@]}" | jq -cRs --arg base "$base" --arg config "$CONFIG_PATH" \
      --argjson stored "$stored" \
      '{ok: true, locked: true, base: $base, configPath: $config, keyringStored: $stored,
        issues: (split("\n") | map(select(. != ""))), remotes: []}'
    exit 0
  fi
  [[ -n $listing ]] || issues+=(noRemotes)

  local name type mounted mode rows=()
  while IFS=$'\t' read -r name type; do
    [[ -z $name ]] && continue
    valid_remote "$name" || continue
    in_csv "$name" "$excluded" && continue
    mounted=false
    mode=""
    if mountpoint -q "$base/$name" 2>/dev/null; then
      mounted=true
      mode=$(head -c 16 "$base/.$name.mode" 2>/dev/null)
    fi
    forced=false
    in_csv "$name" "$readonly_csv" && forced=true
    rows+=("$(jq -cn --arg name "$name" --arg type "$type" --arg path "$base/$name" \
      --arg mode "$mode" --argjson mounted "$mounted" --argjson forced "$forced" \
      '{name: $name, type: $type, path: $path, mounted: $mounted, mode: $mode, forcedReadOnly: $forced}')")
  done <<<"$listing"

  ((${#rows[@]})) || rows=("null")
  local issues_json
  issues_json=$(printf '%s\n' "${issues[@]}" | jq -cRs 'split("\n") | map(select(. != ""))')
  local stored=false
  [[ -n ${RCLONE_CONFIG_PASS:-} ]] && stored=true
  printf '%s\n' "${rows[@]}" | jq -cs --arg base "$base" --arg config "$CONFIG_PATH" \
    --argjson issues "$issues_json" --argjson stored "$stored" \
    '{ok: true, locked: false, base: $base, configPath: $config, keyringStored: $stored,
      issues: $issues, remotes: map(select(. != null))}'
}

cmd_mount() {
  local base name mode readonly_csv open_after
  expand_base "$1"; base="$BASE"
  name="$2"
  mode="$3"
  readonly_csv="$4"
  open_after="$5"

  valid_remote "$name" || json_error invalidName "$name"
  case "$mode" in full|writes|read-only) ;; *) json_error invalidMode "$mode" ;; esac
  in_csv "$name" "$readonly_csv" && mode="read-only"

  require_rclone
  require_fuse
  require_config
  load_password
  list_remotes | cut -f1 | grep -qxF -- "$name" || json_error unknownRemote "$name"

  local target="$base/$name"
  local state="$base/.$name.mode"
  if mountpoint -q "$target" 2>/dev/null; then
    jq -cn --arg name "$name" '{ok: true, action: "mount", name: $name, already: true}'
    exit 0
  fi

  local opts=(
    --umask 077
    --dir-cache-time 30s
    --poll-interval 0
    --attr-timeout 1s
    --timeout 30s
    --contimeout 15s
    --low-level-retries 3
    --retries 2
    --daemon
    --daemon-timeout 60s
    --sftp-idle-timeout 30s
  )
  case "$mode" in
    full)
      opts+=(--vfs-cache-mode full --vfs-cache-max-size 5G --vfs-cache-max-age 24h) ;;
    writes)
      opts+=(--vfs-cache-mode writes --vfs-read-chunk-size 32M
             --vfs-read-chunk-size-limit 512M --buffer-size 64M) ;;
    read-only)
      opts+=(--read-only --vfs-cache-mode writes --vfs-read-chunk-size 32M
             --vfs-read-chunk-size-limit 512M) ;;
  esac

  mkdir -p -- "$target" || json_error mountFailed "mkdir $target"
  local err
  err=$(timeout 90 rclone mount "$name:" "$target" "${opts[@]}" 2>&1)

  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    mountpoint -q "$target" && break
    sleep 0.5
  done

  if mountpoint -q "$target"; then
    printf '%s' "$mode" >"$state"
    notify "$(msg mounted "$name" "$target" "$mode")"
    [[ $open_after == 1 ]] && setsid -f env -u LC_ALL xdg-open "$target" >/dev/null 2>&1
    jq -cn --arg name "$name" --arg mode "$mode" '{ok: true, action: "mount", name: $name, mode: $mode}'
  else
    rmdir -- "$target" 2>/dev/null
    json_error mountFailed "$(printf '%s' "$err" | tail -3)"
  fi
}

cmd_unmount() {
  local base name
  expand_base "$1"; base="$BASE"
  name="$2"
  valid_remote "$name" || json_error invalidName "$name"

  local target="$base/$name"
  if mountpoint -q "$target" 2>/dev/null; then require_fuse; fi
  if ! mountpoint -q "$target" 2>/dev/null; then
    rm -f -- "$base/.$name.mode"
    jq -cn --arg name "$name" '{ok: true, action: "unmount", name: $name, already: true}'
    exit 0
  fi

  local err
  if err=$(fusermount3 -uz -- "$target" 2>&1); then
    rm -f -- "$base/.$name.mode"
    rmdir -- "$target" 2>/dev/null
    notify "$(msg unmounted "$name")"
    jq -cn --arg name "$name" '{ok: true, action: "unmount", name: $name}'
  else
    json_error unmountFailed "$err"
  fi
}

cmd_unlock() {
  require_rclone
  require_config
  require_secret_tool
  require_zenity
  local p
  p=$(zenity --password --title="$(msg password)" 2>/dev/null) || json_error cancelled
  [[ -n $p ]] || json_error cancelled
  if ! RCLONE_CONFIG_PASS="$p" rclone listremotes --ask-password=false </dev/null >/dev/null 2>&1; then
    json_error badPassword
  fi
  printf '%s' "$p" | secret-tool store --label="rclone config" service rclone key config ||
    json_error keyringFailed
  jq -cn '{ok: true, action: "unlock"}'
}

# Delete the stored config password. Running mounts keep working (rclone
# already decrypted the config); the next mount asks for the password again.
cmd_forget() {
  require_secret_tool
  secret-tool clear service rclone key config 2>/dev/null
  if [[ -n $(secret-tool lookup service rclone key config 2>/dev/null) ]]; then
    json_error forgetFailed
  fi
  notify "$(msg forgotten)"
  jq -cn '{ok: true, action: "forget"}'
}

case "${1:-}" in
  status) shift; cmd_status "$@" ;;
  mount) shift; cmd_mount "$@" ;;
  unmount) shift; cmd_unmount "$@" ;;
  unlock) cmd_unlock ;;
  forget) cmd_forget ;;
  *) json_error usage "$1" ;;
esac
