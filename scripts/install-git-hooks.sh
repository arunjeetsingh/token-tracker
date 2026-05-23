#!/bin/sh
# Installs token-tracker's local git hooks.
# Hooks live in scripts/git-hooks/ (tracked) and are copied into .git/hooks/.
set -eu
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO_ROOT/scripts/git-hooks"
DST="$REPO_ROOT/.git/hooks"
mkdir -p "$DST"
for hook in "$SRC"/*; do
  [ -f "$hook" ] || continue
  name="$(basename "$hook")"
  cp "$hook" "$DST/$name"
  chmod +x "$DST/$name"
  echo "installed: $DST/$name"
done
echo "Done. Verify: ls -la $DST/"
