#!/usr/bin/env bash
# Remove the symlinks and the hooks block. Leaves your data in ai-mode/ alone.
set -euo pipefail
DEST="${CLAUDE_DIR:-$HOME/.claude}"
for m in pair solve study debt; do [ -L "$DEST/skills/$m" ] && rm -f "$DEST/skills/$m"; done
for h in safe-run mode-set mode-guard mode-banner pair-unlock debt-add debt-report; do
  [ -L "$DEST/hooks/$h.sh" ] && rm -f "$DEST/hooks/$h.sh"
done
[ -L "$DEST/AI-PLAYBOOK.md" ] && rm -f "$DEST/AI-PLAYBOOK.md"
if [ -e "$DEST/settings.json" ] && command -v jq >/dev/null; then
  jq 'del(.hooks)' "$DEST/settings.json" > "$DEST/settings.json.new"
  mv "$DEST/settings.json.new" "$DEST/settings.json"
fi
echo "uninstalled. ai-mode/ data left in place; remove the CLAUDE.md section by hand."
