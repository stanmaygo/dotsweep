#!/usr/bin/env bash
# Copy the prompt from the engine repo, then prove the packaging still holds.
#
# One direction only, and deliberately: this repo is a mirror. A change made
# here is overwritten by the next run, while dotsweep.com/skill.md — what the
# paste-one-message install fetches — keeps serving the engine's copy. Two
# installs of one skill then behave differently with nothing reporting it.
set -euo pipefail

# No default. The engine repository is private and naming its checkout path here
# would publish that path to everyone who reads this file.
ENGINE="${DOTSWEEP_ENGINE:?set DOTSWEEP_ENGINE to the engine repository checkout}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ENGINE/skills/dotsweep/SKILL.md"
DEST="$ROOT/skills/dotsweep/SKILL.md"

[ -f "$SRC" ] || { echo "no skill at $SRC — check DOTSWEEP_ENGINE" >&2; exit 1; }

if cmp -s "$SRC" "$DEST"; then
  echo "already in sync"
else
  cp "$SRC" "$DEST"
  echo "skills/dotsweep/SKILL.md ← $SRC"
fi

# The version comes with it. Leaving plugin.json to a human is a step that gets
# forgotten, and its failure is silent at install time — which is exactly what
# the validator below catches, so the validator should not also be the only
# thing preventing it.
python3 "$ROOT/scripts/bump-version.py"

python3 "$ROOT/scripts/validate-package.py"
