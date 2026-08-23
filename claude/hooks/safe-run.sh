#!/usr/bin/env bash
# Fail-open wrapper for the AI-mode hooks.
#
# A hook script with a syntax error breaks every Write, Edit and Bash call in
# every session, and repairing it needs exactly those tools - so the failure is
# unrecoverable from inside Claude Code. This wrapper degrades that into
# "enforcement silently off", which is the right direction for a guard you
# cannot fix while it is broken.
#
# Keep this file tiny and leave it alone. It is the thing with no safety net.
S="${1:-}"
[ -r "$S" ] || exit 0
bash -n "$S" 2>/dev/null || exit 0
shift
exec bash "$S" "$@"
