# CLAUDE.md — vcare Documentation Hub

This repo is the **documentation hub** for the vcare Virtual Care Platform. It does **not** contain
application code. It aggregates the *cross-cutting* subset of every service's docs so that a human or
an AI agent can understand the whole system from one place — without cloning every service.

**There is no `.claude/` directory here, by design.** The spokes own the development workflow
(commands, agents, skills, settings); the hub only aggregates. Do not add one.

## The hub-and-spoke model

```
   spoke repos (own their docs)                    this hub (aggregated view)
 ┌──────────────────────────────┐    sync     ┌──────────────────────────────────┐
 │ vcare-identity-api           │ ──────────▶ │ product/prd.md (source of intent)│
 │   (identity-service)         │  card +     │ catalog/  (service cards)        │
 │   docs/, contracts/          │  openapi    │ contracts/ (synced OpenAPI)      │
 ├──────────────────────────────┤             │ architecture/ (landscape,        │
 │ vcare-care-api               │ ──────────▶ │               data-ownership)    │
 │   (care-service)             │             │ adr/  glossary.md  INDEX.md      │
 │   docs/, contracts/          │             └──────────────────────────────────┘
 └──────────────────────────────┘
        ▲                                                    │
        └────────── spokes read the hub at ../vcare-hub ─────┘
```

**Source-of-truth rule:** per-service docs live **in the service repo**, next to the code, so they
stay truthful. This hub holds only the aggregated *subset* (service card + contracts + platform-level
architecture/ADRs/glossary + the PRD). Synced files (`catalog/*.card.md`, `contracts/*`) are
populated by `scripts/sync-from-spoke.sh` and are **never hand-edited**. If a card or contract here
disagrees with the spoke, **the spoke wins** and the sync is stale — re-run it.

## How an agent should retrieve docs (escalation — cheapest first)

Do **not** clone repos to read them. Escalate only when the cheaper step didn't answer it:

1. **Current service** — if you're working in a service repo, grep it locally.
2. **Hub `INDEX.md`** — the router. Where does the answer live?
3. **Hub content** — most cross-service questions (a contract, who-owns-what, who-calls-whom, what
   the PRD requires) are answered *here*. Stop.
4. **Sibling repo checked out locally?** If you need a detail the hub doesn't carry, first check
   whether that service's repo is present next to this one (`../vcare-identity-api`,
   `../vcare-care-api`). If it is, read its docs **directly on disk**. **If you're not sure whether
   it's checked out, ASK the user** ("Is `<service>` cloned locally?") before reaching out — don't
   assume it isn't.
5. **GitHub MCP peek** — only if the repo is **not** local, read the specific file live via GitHub
   MCP. Still no clone.
6. **Clone** — only when you are going to actually **change or run** that other service.

## What lives here
| Path | What |
|---|---|
| `INDEX.md` | top-level router across all services — READ FIRST |
| `product/prd.md` | the PRD — **source of intent**; every service's scope traces back here |
| `catalog/` | service catalog + one card per service (cards synced) |
| `contracts/` | synced OpenAPI from each spoke (`<service>.openapi.yaml`) |
| `architecture/` | landscape (C4 + dependency graph + the three integration cases), platform data-ownership map |
| `adr/` | platform-level architecture decisions |
| `glossary.md` | ubiquitous language — shared terms, defined once |
| `scripts/` | `sync-from-spoke.sh` (aggregate a spoke) + `check-freshness.sh` (drift check, run manually) |
| `TODO.md` | deferred: docs-lint CI, CI-triggered sync, events/AsyncAPI, docs-MCP search |
| `docs/superpowers/` | design history — the setup design spec and its implementation plan |

## Who may edit what
| Hub path | Edited by | How |
|---|---|---|
| `architecture/landscape.md` | a spoke's `/system-design` for a cross-service topic | direct edit in the hub; set `last_verified` |
| `architecture/data-ownership.md` | a spoke's `/system-design` for a cross-service topic | direct edit in the hub; set `last_verified` |
| `adr/` | a spoke's `/system-design` when the decision is platform-wide | new append-only ADR; supersede, never rewrite |
| `glossary.md` | a spoke's `/system-design` when a shared term is introduced or sharpened | add the term before it spreads |
| `catalog/*.card.md`, `contracts/*` | **nobody by hand** | only `scripts/sync-from-spoke.sh` |
| `catalog/service-catalog.md` | platform-team when a service is added or changes tier/status | direct edit |
| `product/prd.md` | product owner | direct edit; scope changes flow from here into the spokes |

## Spokes own the dev workflow
Each spoke runs the full per-module workflow (`/system-design → /brainstorm → /construct-spec →
/develop → /write-tests → /manual-qa → /review-code → /update-docs`) with its own `.claude/`
commands, agents, and skills. The hub does **not** run that workflow — it only aggregates the
cross-cutting subset. Drift prevention (freshness/link/contract-drift checks in CI) is deferred —
see `TODO.md`.
