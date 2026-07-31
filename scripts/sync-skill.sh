#!/usr/bin/env bash
# Copy the prompt from the engine repo, then prove the packaging still holds.
#
# One direction only, and deliberately: this repo is a mirror. A change made
# here is overwritten by the next run, while dotsweep.com/skill.md — what the
# paste-one-message install fetches — keeps serving the engine's copy. Two
# installs of one skill then behave differently with nothing reporting it.
set -euo pipefail

ENGINE="${DOTSWEEP_ENGINE:-$HOME/MyApps/brandsearch}"
SRC="$ENGINE/skills/dotsweep/SKILL.md"
DEST="$(cd "$(dirname "$0")/.." && pwd)/skills/dotsweep/SKILL.md"

[ -f "$SRC" ] || { echo "no skill at $SRC — set DOTSWEEP_ENGINE" >&2; exit 1; }

if cmp -s "$SRC" "$DEST"; then
  echo "already in sync"
else
  cp "$SRC" "$DEST"
  echo "skills/dotsweep/SKILL.md ← $SRC"
fi

# The version in plugin.json is not synced: it is this repo's release number and
# the validator is what keeps it aligned with the frontmatter.
python3 "$(dirname "$0")/validate-package.py"
