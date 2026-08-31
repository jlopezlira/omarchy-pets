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
omarchy plugin disable jlopezlira.pet >/dev/null 2>&1 || true
rm -rf ~/.config/omarchy/plugins/jlopezlira.pet
echo "notifications: back to Omarchy's toasts"
omarchy plugin enable omarchy.notifications >/dev/null 2>&1 || true
rm -rf ~/.config/omarchy/plugins/jlopezlira.notifications
echo "scripts"
rm -f ~/.local/bin/pet-health ~/.local/bin/pet-agent-state ~/.local/bin/pet-fetch
if [ -f /usr/local/bin/ttfx ] && grep -q 'pet screensaverOn' /usr/local/bin/ttfx; then
  echo "screensaver hook (sudo)"
  sudo rm -f /usr/local/bin/ttfx
fi
if [ $purge = 1 ]; then
  rm -rf ~/.config/omarchy/pet.json ~/.config/omarchy/pets ~/.local/state/omarchy/pet
fi
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
omarchy restart shell >/dev/null 2>&1 || true
echo "Done."
