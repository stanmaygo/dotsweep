#!/usr/bin/env python3
"""Carry the skill's version into the plugin manifest.

The version lives in two files because two installers read two different ones:
`metadata.version` in the skill frontmatter, and `version` in
`.claude-plugin/plugin.json`. `marketplace.json` deliberately carries none, so
the manifest stays the single source for a harness that asks.

Keeping them in step was a manual step, and a forgotten one fails at install
time rather than here. validate-package.py still asserts they match — this just
stops that assertion being the only thing that prevents it.
"""

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SKILL = ROOT / "skills" / "dotsweep" / "SKILL.md"
MANIFEST = ROOT / ".claude-plugin" / "plugin.json"

frontmatter = SKILL.read_text().split("---", 2)
if len(frontmatter) < 3:
    sys.exit("SKILL.md has no frontmatter to read a version from")

found = re.search(r"(?m)^\s+version:\s*[\"']?([0-9][^\"'\s]*)", frontmatter[1])
if not found:
    sys.exit("SKILL.md frontmatter has no metadata.version")
version = found.group(1)

doc = json.loads(MANIFEST.read_text())
if doc.get("version") == version:
    sys.exit(0)

doc["version"] = version
MANIFEST.write_text(json.dumps(doc, indent=2) + "\n")
print(f"plugin.json version -> {version}")
