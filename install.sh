#!/bin/bash
# Enable the rclone mounts plugin and choose where it sits in the bar.
#   ./install.sh                 # asks for the section (gum)
#   ./install.sh right           # left | centerBegin | centerEnd | right | tray
set -euo pipefail

ID="snouhaud.rclone-mounts"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

omarchy plugin validate "$DIR"
chmod +x "$DIR/rclone-mounts.sh"
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true

lang=$(head -n 1 "${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/language" 2>/dev/null | tr -d '[:space:]')
lang="${lang:-${LC_ALL:-${LC_MESSAGES:-${LANG:-en}}}}"
if [[ ${lang:0:2} == fr ]]; then
  header="Où placer « rclone mounts » dans la barre ?"
  invalid="Section invalide"
else
  header="Where should \"rclone mounts\" go in the bar?"
  invalid="Invalid section"
fi

section="${1:-}"
if [[ -z $section ]]; then
  section=$(printf '%s\n' right centerEnd centerBegin left tray |
    gum choose --header="$header" --selected right)
fi
[[ $section =~ ^(left|centerBegin|centerEnd|right|tray)$ ]] || { echo "$invalid: $section" >&2; exit 1; }

# Already in the bar? move it; otherwise enable it at that spot.
if jq -e --arg id "$ID" '[.bar.layout[][]? | .id] | index($id)' ~/.config/omarchy/shell.json >/dev/null 2>&1; then
  omarchy bar move "$ID" --section "$section"
else
  omarchy plugin enable "$ID" --section "$section"
fi
