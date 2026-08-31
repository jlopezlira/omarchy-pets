#!/bin/bash
# Omarchy Pet installer.
#
#   ./install.sh                 install everything that needs no root
#   ./install.sh --screensaver   also install the screensaver hook (asks for sudo once)
#   ./install.sh --pet <id>      use another built-in Codex pet (default: rocky)
#
# What it does, in order:
#   1. copies the shell plugin to ~/.config/omarchy/plugins/jlopezlira.pet/
#   2. installs pet-health, pet-agent-state and pet-fetch into ~/.local/bin/
#   3. installs the default config to ~/.config/omarchy/pet.json (kept if present)
#   4. downloads the pet's spritesheet (OpenAI CDN, personal use) into ~/.config/omarchy/pets/<id>/
#   5. clones Omarchy's notification service and hides its toast stack, so the pet delivers notifications
#   6. adds the Claude Code / Codex hooks (backups in ~/.local/state/config-backups/)
#   7. enables the plugin and restarts the shell
#   8. (--screensaver) installs /usr/local/bin/ttfx so the Omarchy screensaver shows the pet
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
pet=rocky; screensaver=0
while [ $# -gt 0 ]; do
  case $1 in
    --screensaver) screensaver=1 ;;
    --pet) pet=$2; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac; shift
done
for cmd in omarchy omarchy-shell hyprctl jq pw-play curl; do
  command -v "$cmd" >/dev/null || { echo "missing: $cmd (is this an Omarchy system?)" >&2; exit 1; }
done

echo "1/8 plugin"
mkdir -p ~/.config/omarchy/plugins/jlopezlira.pet
cp "$here"/plugin/jlopezlira.pet/* ~/.config/omarchy/plugins/jlopezlira.pet/

echo "2/8 scripts"
mkdir -p ~/.local/bin
install -m 755 "$here"/bin/pet-health "$here"/bin/pet-agent-state "$here"/bin/pet-fetch ~/.local/bin/

echo "3/8 config"
[ -f ~/.config/omarchy/pet.json ] || cp "$here"/config/pet.json ~/.config/omarchy/pet.json
mkdir -p ~/.local/state/omarchy/pet/agents
[ -f ~/.local/state/omarchy/pet/position.json ] || echo '{}' > ~/.local/state/omarchy/pet/position.json

echo "4/8 pet: $pet"
if [ "$pet" = rocky ] && [ -f "$here"/pets/rocky/pet.json ]; then
  mkdir -p ~/.config/omarchy/pets/rocky
  cp "$here"/pets/rocky/pet.json ~/.config/omarchy/pets/rocky/pet.json
fi
~/.local/bin/pet-fetch "$pet"
if [ "$pet" != rocky ]; then
  # the plugin reads ~/.config/omarchy/pets/rocky by default; point it at the chosen pet
  sed -i "s|/.config/omarchy/pets/rocky/|/.config/omarchy/pets/$pet/|" ~/.config/omarchy/plugins/jlopezlira.pet/Service.qml
fi

echo "5/8 notifications: hide Omarchy's toast stack (the pet shows them instead)"
if [ ! -d ~/.config/omarchy/plugins/jlopezlira.notifications ]; then
  omarchy plugin clone omarchy.notifications >/dev/null
fi
sed -i 's|^      visible: popupModel.count > 0$|      // Omarchy Pet delivers notifications; the top-right toast stack stays hidden.\n      visible: false|' \
  ~/.config/omarchy/plugins/jlopezlira.notifications/Service.qml

echo "6/8 agent hooks"
python3 "$here"/hooks/install-hooks.py

echo "7/8 enable"
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
sleep 1
omarchy plugin enable jlopezlira.pet >/dev/null 2>&1 || true
omarchy restart shell >/dev/null 2>&1 || true

if [ $screensaver = 1 ]; then
  echo "8/8 screensaver (sudo)"
  sudo install -m 755 "$here"/screensaver/ttfx /usr/local/bin/ttfx
else
  echo "8/8 screensaver: skipped (run again with --screensaver, needs sudo)"
fi
echo
echo "Done. The pet sits bottom-right; drag it wherever you like. Status: omarchy-shell pet status"
echo "Note: if Do Not Disturb is on, no notification is shown (same as before)."
