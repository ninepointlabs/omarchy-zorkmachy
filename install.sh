#!/bin/bash
# Copy this checkout into the Omarchy plugin directory and enable it.
# Re-run after pulling changes; the shell hot-reloads the copied files.

set -euo pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$src/manifest.json")"
dest="$HOME/.config/omarchy/plugins/$id"

mkdir -p "$dest"
# Only ship what the shell needs; git history, tests and screenshots stay behind.
for entry in manifest.json Games.js Service.qml BarWidget.qml Panel.qml README.md LICENSE games; do
  [[ -e "$src/$entry" ]] && cp -r "$src/$entry" "$dest/"
done

if command -v omarchy-shell >/dev/null 2>&1 && omarchy-shell shell ping >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  if ! omarchy plugin list --json 2>/dev/null | grep -q "\"$id\"[^}]*\"enabled\": *true"; then
    omarchy plugin enable "$id" --section "${1:-right}" || true
  fi
fi

echo "Installed $id to $dest"
