#!/usr/bin/env python3
"""Check the packaging surfaces a skill installer sees, without any dependency.

The prompt is exercised by suites that live with the engine. Nothing tested
the *packaging*: the frontmatter a harness parses, the version in three files,
whether the root SKILL.md still points at a real file. Those break silently —
the tests stay green while `npx skills add` or `/plugin install` gets nothing.

Deliberately dependency-free so it runs before any install step, in CI and on a
laptop, with nothing but python3.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SKILL_PATH = ROOT / "skills" / "dotsweep" / "SKILL.md"
PLUGIN_PATH = ROOT / ".claude-plugin" / "plugin.json"
MARKETPLACE_PATH = ROOT / ".claude-plugin" / "marketplace.json"

errors: list[str] = []


def fail(message: str) -> None:
    errors.append(message)


# The root SKILL.md is the artifact a manual installer copies and the path the
# skills CLI looks for first. It is a symlink so there is exactly one copy of
# the prompt in the repo; a broken link is the failure this catches, because
# nothing else in CI reads it.
root_skill = ROOT / "SKILL.md"
if not root_skill.is_symlink():
    fail("SKILL.md at the repo root must be a symlink, not a second copy of the prompt")
elif root_skill.resolve() != SKILL_PATH.resolve():
    fail(f"SKILL.md points at {root_skill.resolve()}, want {SKILL_PATH}")

# Codex and Warp read AGENTS.md, Claude Code reads CLAUDE.md, and the contract
# is the same one. A symlink rather than a copy, because two files drift and the
# packaging rules below are exactly what a second agent needs to not break.
agents_md = ROOT / "AGENTS.md"
if not agents_md.is_symlink():
    fail("AGENTS.md must be a symlink to CLAUDE.md, not a second copy")
elif agents_md.resolve() != (ROOT / "CLAUDE.md").resolve():
    fail(f"AGENTS.md points at {agents_md.resolve()}, want CLAUDE.md")

# The skill is not Claude-only, and the thing that keeps that true is that
# nothing in the prompt names a harness. .claude-plugin/ is optional packaging
# for one host; the prompt itself must read the same everywhere.
if not (ROOT / "agents" / "openai.yaml").exists():
    fail("missing agents/openai.yaml, the Codex display surface")

if not SKILL_PATH.exists():
    fail(f"missing {SKILL_PATH.relative_to(ROOT)}")
    print("\n".join(f"  ✘ {e}" for e in errors))
    raise SystemExit(1)

skill = SKILL_PATH.read_text()
plugin = json.loads(PLUGIN_PATH.read_text())
marketplace = json.loads(MARKETPLACE_PATH.read_text())

frontmatter_match = re.match(r"\A---\n(.*?)\n---\n", skill, re.DOTALL)
if frontmatter_match is None:
    fail("SKILL.md must open with YAML frontmatter")
    frontmatter = ""
else:
    frontmatter = frontmatter_match.group(1)

# A harness that does not understand a key may reject the whole skill rather
# than ignore the line. Keep the frontmatter to what every host reads.
for key in ("compatibility:", "allowed-tools:", "^version:"):
    pattern = key if key.startswith("^") else rf"^{re.escape(key)}"
    if re.search(pattern, frontmatter, re.MULTILINE):
        fail(f"nonportable frontmatter key: {key.lstrip('^').rstrip(':')}")

if not re.search(r"(?m)^name: dotsweep$", frontmatter):
    fail("frontmatter must declare `name: dotsweep`")

# The description is the whole of what a model sees before deciding whether to
# load the skill. An empty or absent one makes the skill undiscoverable in
# exactly the situation it exists for.
description = re.search(r"(?m)^description: (.+)$", frontmatter)
if description is None:
    fail("frontmatter has no description")
elif len(description.group(1)) < 200:
    fail("description is too short to route on; say when to use this, not just what it is")

version_match = re.search(r'(?m)^\s+version:\s*["\']([^"\']+)["\']\s*$', frontmatter)
if version_match is None:
    fail("SKILL.md needs metadata.version (a top-level `version:` is not portable)")
else:
    versions = {version_match.group(1), str(plugin.get("version", ""))}
    if len(versions) != 1:
        fail(f"version mismatch between SKILL.md and plugin.json: {sorted(versions)}")

# marketplace.json omits a version on purpose so plugin.json stays the single
# source of truth for what is installed. Two version fields drift.
if "version" in marketplace:
    fail("marketplace.json must not carry a version; plugin.json owns it")
if [p.get("name") for p in marketplace.get("plugins", [])] != [plugin.get("name")]:
    fail("marketplace.json must list exactly the plugin in plugin.json")

# The rule the whole codebase is built around. If it ever stops being stated in
# the skill, a model has no reason to pass on a `?` to the user, and an
# unverified guess reads as a fact.
if "?` is not `+`" not in skill and "? is not +" not in skill:
    fail("SKILL.md must still tell the reader that an unverified result is not availability")

# Publishing the skill separates it from the checkout, so a path only valid on
# one laptop becomes a dead end for everyone else.
for absolute in re.findall(r"(?m)^.*(?:cd |~/)(?:MyApps|Users)/\S*", skill):
    fail(f"SKILL.md refers to a machine-specific path: {absolute.strip()}")

# The hosted API must be reachable without the binary, and only from hostnames
# we control. A guessed hostname answering plausibly is the one failure mode
# that costs a user money.
hosts = set(re.findall(r"https://([a-z0-9.-]+)/(?:check|whois|tlds|price)", skill))
if hosts - {"dotsweep.com"}:
    fail(f"SKILL.md names an API host that is not dotsweep.com: {sorted(hosts)}")
if "DOTSWEEP_API" not in skill:
    fail("SKILL.md must let a self-hoster override the endpoint via DOTSWEEP_API")

# Naming a harness in the prompt is how a portable skill quietly becomes a
# single-host one: the next edit reads "in Claude Code, do X" as licence to
# assume that host's tools exist.
for harness in ("Claude", "Codex", "Cursor", "OpenCode", "Warp"):
    if re.search(rf"\b{harness}\b", skill):
        fail(f"SKILL.md names a harness ({harness}); the prompt must read the same in all of them")

# A skill loads in full on every invocation, so its length is a cost paid on
# every use rather than once at install.
lines = len(skill.splitlines())
if lines > 400:
    fail(f"SKILL.md is {lines} lines, over the 400-line budget")

if errors:
    print(f"✘ {len(errors)} problem(s) in the dotsweep package:")
    print("\n".join(f"  - {e}" for e in errors))
    raise SystemExit(1)

print(f"dotsweep package v{version_match.group(1)} is valid ({lines} lines)")
