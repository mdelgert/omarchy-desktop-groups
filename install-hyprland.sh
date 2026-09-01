#!/bin/bash
# Install the desktop-groups Lua module into ~/.config/hypr and wire it into
# hyprland.lua. Safe to re-run: the module is overwritten, the require line is
# added only once.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HYPR_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
MODULE="$HYPR_DIR/desktop-groups.lua"
CONFIG="$HYPR_DIR/hyprland.lua"
MARKER="hypr.desktop-groups"

DESKTOPS="${DESKTOPS:-3}"

die() { echo "error: $*" >&2; exit 1; }

[[ -d $HYPR_DIR ]] || die "no Hyprland config directory at $HYPR_DIR"
[[ -f $CONFIG ]] || die "no hyprland.lua at $CONFIG -- is this an Omarchy system?"

install -Dm644 "$SRC_DIR/hypr/desktop-groups.lua" "$MODULE"
echo "installed $MODULE"

if grep -qF "$MARKER" "$CONFIG"; then
  echo "hyprland.lua already requires the module -- left unchanged"
else
  # Anything already in hyprland.lua is the user's, so keep a copy before
  # appending. Timestamped so repeated installs never clobber an older backup.
  backup="$CONFIG.bak.$(date +%s)"
  cp "$CONFIG" "$backup"
  echo "backed up $CONFIG -> $backup"

  cat >>"$CONFIG" <<LUA

-- omarchy-desktop-groups -- https://github.com/mdelgert/omarchy-desktop-groups
-- Switch every monitor to a new set of workspaces with SUPER+F1..F$DESKTOPS.
require("$MARKER").setup({ desktops = $DESKTOPS })
LUA
  echo "wired into $CONFIG"
fi

if command -v hyprctl >/dev/null 2>&1 && [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
  hyprctl reload >/dev/null
  errors=$(hyprctl configerrors 2>/dev/null || true)

  # configerrors prints nothing on success. Anything here means the reload
  # rejected something, and the user needs to see it rather than a bare "done".
  if [[ -n ${errors//[[:space:]]/} ]]; then
    echo
    echo "Hyprland reported config errors:" >&2
    echo "$errors" >&2
    exit 1
  fi

  echo "reloaded Hyprland -- press SUPER+F1 through SUPER+F$DESKTOPS"
else
  echo "not inside a running Hyprland session -- changes apply at next login"
fi
