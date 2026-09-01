#!/bin/bash
# Remove the desktop-groups module and its require line from hyprland.lua.
#
# Workspace rules and bindings live only in the running compositor, so they are
# gone after the reload. Workspaces themselves are not touched: any windows on
# desktop 2 or 3 stay on the workspaces they are on.

set -euo pipefail

HYPR_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
MODULE="$HYPR_DIR/desktop-groups.lua"
CONFIG="$HYPR_DIR/hyprland.lua"

if [[ -f $CONFIG ]] && grep -qF "hypr.desktop-groups" "$CONFIG"; then
  backup="$CONFIG.bak.$(date +%s)"
  cp "$CONFIG" "$backup"
  echo "backed up $CONFIG -> $backup"

  # Drop the require line plus the comment block the installer wrote above it.
  awk '
    /^-- omarchy-desktop-groups/ { skip = 1 }
    skip && /^require\("hypr\.desktop-groups"\)/ { skip = 0; next }
    skip { next }
    { print }
  ' "$backup" >"$CONFIG"
  # Removing the block leaves the blank line the installer wrote above it, so
  # normalise the trailing whitespace back to a single newline.
  printf '%s\n' "$(<"$CONFIG")" >"$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"

  echo "removed the require from $CONFIG"
fi

[[ -f $MODULE ]] && rm -f "$MODULE" && echo "removed $MODULE"

if command -v hyprctl >/dev/null 2>&1 && [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
  hyprctl reload >/dev/null
  echo "reloaded Hyprland"
fi
