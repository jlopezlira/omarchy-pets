#!/bin/bash
# Omarchy Pet uninstaller: puts everything back the way it was.
#   ./uninstall.sh            remove plugin, scripts, hooks, notification clone
#   ./uninstall.sh --purge    also delete config, downloaded pets and saved state
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
purge=0; [ "${1:-}" = "--purge" ] && purge=1

echo "hooks"
python3 "$here"/hooks/install-hooks.py --remove
echo "plugin"
omarchy plugin disable jlopezlira.pets >/dev/null 2>&1 || true
rm -rf ~/.config/omarchy/plugins/jlopezlira.pets
echo "notifications: back to Omarchy's toasts"
omarchy plugin enable omarchy.notifications >/dev/null 2>&1 || true
rm -rf ~/.config/omarchy/plugins/jlopezlira.notifications
echo "scripts"
rm -f ~/.local/bin/omarchy-pets-health ~/.local/bin/omarchy-pets-agent-state ~/.local/bin/omarchy-pets-fetch ~/.local/bin/omarchy-pets-activity ~/.local/bin/omarchy-pets-list
echo "hyprland rules"
rm -f ~/.config/hypr/omarchy-pets.lua
sed -i '/-- Omarchy Pets (screensaver blur/d; /require("hypr.omarchy-pets")/d' ~/.config/hypr/hyprland.lua 2>/dev/null || true
hyprctl reload >/dev/null 2>&1 || true
if [ -f /usr/local/bin/ttfx ] && grep -q 'pet screensaverOn' /usr/local/bin/ttfx; then
  echo "screensaver hook (sudo)"
  sudo rm -f /usr/local/bin/ttfx
fi
if [ $purge = 1 ]; then
  rm -rf ~/.config/omarchy/pets.json ~/.config/omarchy/pets ~/.local/state/omarchy/pet
fi
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
omarchy restart shell >/dev/null 2>&1 || true
echo "Done."
