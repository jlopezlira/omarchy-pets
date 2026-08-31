#!/bin/bash
# Repository self-check: shell syntax, Python compile, JSON validity and (when
# available) QML lint. Used by prjct's gauntlet and by CI.
set -e
cd "$(dirname "$0")"
for f in install.sh uninstall.sh bin/* screensaver/ttfx; do bash -n "$f"; done
python3 -m py_compile hooks/install-hooks.py
for j in config/pets.json pets/rocky/pet.json plugin/jlopezlira.pets/manifest.json; do jq -e . "$j" >/dev/null; done
if command -v qmllint >/dev/null; then qmllint --no-unqualified-id -I /usr/share/omarchy/shell plugin/jlopezlira.pets/Service.qml 2>&1 | grep -E 'Error|error:' && exit 1 || true; fi
echo "checks passed"
