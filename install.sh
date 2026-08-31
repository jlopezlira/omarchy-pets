#!/bin/bash
# Omarchy Pet installer.
#
#   ./install.sh                 install everything that needs no root
#   ./install.sh --screensaver   also install the screensaver hook (asks for sudo once)
#   ./install.sh --pet <id>      use another built-in Codex pet (default: rocky)
#   ./install.sh --all-pets      download all eight built-in pets up front (~5 MB), so switching is instant
#
# What it does, in order:
#   1. copies the shell plugin to ~/.config/omarchy/plugins/jlopezlira.pets/
#   2. installs omarchy-pets-health, omarchy-pets-agent-state and omarchy-pets-fetch into ~/.local/bin/
#   3. installs the default config to ~/.config/omarchy/pets.json (kept if present)
#   4. downloads the pet's spritesheet (OpenAI CDN, personal use) into ~/.config/omarchy/pets/<id>/
#   5. clones Omarchy's notification service and hides its toast stack, so the pet delivers notifications
#   6. adds the Claude Code / Codex hooks (backups in ~/.local/state/config-backups/)
#   7. enables the plugin and restarts the shell
#   8. adds the Hyprland rules (blurred screensaver layer, hidden screensaver terminal)
#   9. (--screensaver) installs /usr/local/bin/ttfx so the Omarchy screensaver shows the pet
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
pet=rocky; screensaver=0; allpets=0
while [ $# -gt 0 ]; do
  case $1 in
    --screensaver) screensaver=1 ;;
    --pet) pet=$2; shift ;;
    --all-pets) allpets=1 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac; shift
done
for cmd in omarchy omarchy-shell hyprctl jq pw-play curl; do
  command -v "$cmd" >/dev/null || { echo "missing: $cmd (is this an Omarchy system?)" >&2; exit 1; }
done

echo "1/9 plugin"
mkdir -p ~/.config/omarchy/plugins/jlopezlira.pets
cp "$here"/plugin/jlopezlira.pets/* ~/.config/omarchy/plugins/jlopezlira.pets/

echo "2/9 scripts"
mkdir -p ~/.local/bin
install -m 755 "$here"/bin/omarchy-pets-health "$here"/bin/omarchy-pets-agent-state "$here"/bin/omarchy-pets-fetch "$here"/bin/omarchy-pets-activity "$here"/bin/omarchy-pets-list ~/.local/bin/

echo "3/9 config"
[ -f ~/.config/omarchy/pets.json ] || cp "$here"/config/pets.json ~/.config/omarchy/pets.json
mkdir -p ~/.local/state/omarchy/pets/agents
[ -f ~/.local/state/omarchy/pets/position.json ] || echo '{}' > ~/.local/state/omarchy/pets/position.json

echo "4/9 pet: $pet"
if [ "$pet" = rocky ] && [ -f "$here"/pets/rocky/pet.json ]; then
  mkdir -p ~/.config/omarchy/pets/rocky
  cp "$here"/pets/rocky/pet.json ~/.config/omarchy/pets/rocky/pet.json
fi
~/.local/bin/omarchy-pets-fetch "$pet"
[ $allpets = 1 ] && ~/.local/bin/omarchy-pets-fetch --all
if [ "$pet" != rocky ]; then
  # remember the chosen pet in the settings file
  jq --arg p "$pet" '.pet = $p' ~/.config/omarchy/pets.json > ~/.config/omarchy/pets.json.tmp && mv ~/.config/omarchy/pets.json.tmp ~/.config/omarchy/pets.json
fi

echo "5/9 notifications: hide Omarchy's toast stack (the pet shows them instead)"
if [ ! -d ~/.config/omarchy/plugins/jlopezlira.notifications ]; then
  omarchy plugin clone omarchy.notifications >/dev/null
fi
sed -i 's|^      visible: popupModel.count > 0$|      // Omarchy Pet delivers notifications; the top-right toast stack stays hidden.\n      visible: false|' \
  ~/.config/omarchy/plugins/jlopezlira.notifications/Service.qml

echo "6/9 agent hooks"
python3 "$here"/hooks/install-hooks.py

echo "7/9 enable"
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
sleep 1
omarchy plugin enable jlopezlira.pets >/dev/null 2>&1 || true
omarchy restart shell >/dev/null 2>&1 || true

echo "8/9 hyprland rules"
cp "$here"/hypr/omarchy-pets.lua ~/.config/hypr/omarchy-pets.lua
grep -q 'hypr.omarchy-pets' ~/.config/hypr/hyprland.lua || printf '\n-- Omarchy Pets (screensaver blur + hidden screensaver terminal)\nrequire("hypr.omarchy-pets")\n' >> ~/.config/hypr/hyprland.lua
hyprctl reload >/dev/null 2>&1 || true

if [ $screensaver = 1 ]; then
  echo "9/9 screensaver (sudo)"
  sudo install -m 755 "$here"/screensaver/ttfx /usr/local/bin/ttfx
else
  echo "9/9 screensaver: skipped (run again with --screensaver, needs sudo)"
fi
echo
echo "Done. The pet sits bottom-right; drag it wherever you like. Right-click it to switch pets. Status: omarchy-shell pets status"
echo "Note: if Do Not Disturb is on, no notification is shown (same as before)."
