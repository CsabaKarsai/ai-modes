#!/usr/bin/env bash
# Install the AI usage modes into ~/.claude (or $CLAUDE_DIR).
#
# Symlinks the skills, hooks and playbook back to this repo, so editing a mode
# in place shows up as a diff here. guard.conf is copied, not linked, because it
# is meant to be tuned per machine. Anything replaced is backed up first.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/claude"
DEST="${CLAUDE_DIR:-$HOME/.claude}"
BACKUP="$DEST/backups/ai-modes-$(date -u +%Y%m%dT%H%M%SZ)"

command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

mkdir -p "$DEST"/{hooks,skills,rules,ai-mode/sessions,ai-mode/unlocked,backups}

keep() { [ -e "$1" ] && [ ! -L "$1" ] && { mkdir -p "$BACKUP"; cp -a "$1" "$BACKUP/"; }; return 0; }
link() { keep "$2"; rm -rf "$2"; ln -s "$1" "$2"; }

for m in pair solve study debt; do link "$SRC/skills/$m" "$DEST/skills/$m"; done
for h in "$SRC"/hooks/*.sh; do chmod +x "$h"; link "$h" "$DEST/hooks/$(basename "$h")"; done
link "$SRC/AI-PLAYBOOK.md" "$DEST/AI-PLAYBOOK.md"
for r in "$SRC"/rules/*.md; do link "$r" "$DEST/rules/$(basename "$r")"; done

if [ -e "$DEST/ai-mode/guard.conf" ]; then
  echo "kept existing ai-mode/guard.conf"
else
  cp "$SRC/ai-mode/guard.conf" "$DEST/ai-mode/guard.conf"
fi

SETTINGS="$DEST/settings.json"
[ -e "$SETTINGS" ] || echo '{}' > "$SETTINGS"
keep "$SETTINGS"
jq -s '.[0] * .[1]' "$SETTINGS" "$SRC/settings.hooks.json" > "$SETTINGS.new"
mv "$SETTINGS.new" "$SETTINGS"

echo "installed into $DEST"
[ -d "$BACKUP" ] && echo "replaced files backed up to $BACKUP"

# The modes section now loads from rules/ai-modes.md. An older install appended it to
# CLAUDE.md; a second copy there would load the rules twice.
if grep -q '^## AI usage modes' "$DEST/CLAUDE.md" 2>/dev/null; then
  echo
  echo "Remove the '## AI usage modes' section from $DEST/CLAUDE.md:"
  echo "it now loads from $DEST/rules/ai-modes.md."
fi

echo
echo "Verify inside Claude Code (not a plain shell - hooks only run there):"
echo "  ask Claude to write a file while in pair; it should be denied."
