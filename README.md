# dotsweep — an agent skill for checking domain name availability and prices

[![License: MIT](https://img.shields.io/badge/License-MIT-black.svg)](LICENSE)
[![Live API](https://img.shields.io/badge/API-dotsweep.com-35c98a)](https://dotsweep.com/docs)
[![MCP server](https://img.shields.io/badge/MCP-dotsweep.com%2Fmcp-35c98a)](https://dotsweep.com/setup)

Teaches an AI agent to check whether a domain name is free across 1,200+
extensions — with the **renewal** price, the registry's minimum term, and who is
allowed to register it. No API key, no account, nothing to install beyond this
file.

**It never reports an unreachable registry as available.** That is the point.
A raw `whois` returns text for a throttled or rate-limited registry that reads
like a not-found, so an agent rolling its own check reports a **taken domain as
free** — the one wrong answer that costs someone money.

## Install

**Paste this into any agent that can write files:**

> Add a skill called dotsweep, for checking domain availability. Fetch
> https://dotsweep.com/skill.md and save it verbatim as `dotsweep/SKILL.md`
> inside whichever skills directory you read.

**Or from this repo:**

```sh
npx skills add stanmaygo/dotsweep-skill
```

**Or link it into any harness that loads skill instructions:**

```sh
ln -s "$PWD/skills/dotsweep" <your-skills-dir>/dotsweep
```

**Or as a Claude Code plugin:**

```
/plugin marketplace add stanmaygo/dotsweep-skill
/plugin install dotsweep@dotsweep
```

Nothing here is Claude-specific. The runtime artifact is
`skills/dotsweep/SKILL.md` — portable Markdown with portable frontmatter.
`agents/openai.yaml` supplies the Codex display surface; `.claude-plugin/` is
optional extra packaging for one harness, not a dependency of the skill.

## What the agent gets

```sh
curl -s -X POST https://dotsweep.com/check \
  -H 'Content-Type: application/json' \
  -d '{"domains":["acmeforge.com","acmeforge.io","acmeforge.ai"]}'
```

```json
{ "domain": "acmeforge.io", "status": "available", "confidence": "certain",
  "source": "rdap",
  "price": { "currency": "USD", "registration": 28.12, "renewal": 51.80 } }
```

- `status` — `available`, `taken` or `unknown`
- `confidence` — `certain` (a registry answered) or `estimated` (DNS only).
  **`estimated` is never a green light**; an unreachable registry cannot
  produce a confident "available".
- `price` — first year *and* renewal, because the renewal is the number paid
  every year after the first and is the one most tools hide.
- `policy` — minimum term (`.ai` sells two years at a time), eligibility rules,
  and extensions that sell to nobody at all.

## Why a skill and not just `whois`

| | this skill | `whois` |
|---|---|---|
| Distinguishes *refused* from *not found* | **yes** | no |
| Works for `.dev` / `.app` | **yes** | no server exists |
| One host for every extension | **yes** | different per TLD |
| Renewal price | **yes** | no price at all |
| Registry minimum term | **yes** | no |
| Eligibility rules | **yes** | no |

## There is also an MCP server

Same engine, same data, for clients that take a URL rather than a file — which
includes the phone apps, where nothing can be installed:

```
https://dotsweep.com/mcp
```

Tools: `check_domains`, `whois`, `list_tlds`. Setup click-path at
[dotsweep.com/setup](https://dotsweep.com/setup).

## Endpoint

The skill calls `https://dotsweep.com` by default and honours `DOTSWEEP_API`
for anyone running their own instance. Reference:
[dotsweep.com/docs](https://dotsweep.com/docs) and
[/llms.txt](https://dotsweep.com/llms.txt).

## Limits worth knowing

- **Premium and reserved names** return the same registry answer as an ordinary
  free domain. Every quoted price is a floor, not a quote.
- **Prices are one registrar's per row**, and each row says which.
- **A TLD with no eligibility entry has not been checked** — that is not the
  same as having no requirements.

## License

MIT
