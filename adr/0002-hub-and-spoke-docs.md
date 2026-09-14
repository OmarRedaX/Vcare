---
title: "ADR 0002: Hub-and-spoke documentation with sync"
owner: platform-team
service: platform
status: accepted
diataxis: explanation
date: 2026-09-14
last_verified: 2026-09-14
tags: [adr, decision, documentation, ai]
related: [adr-0001-two-service-split, service-catalog]
---

# ADR 0002 — Hub-and-spoke documentation with sync

- **Status:** Accepted
- **Date:** 2026-09-14
- **Deciders:** platform-team

## Context
vcare is three independent git repos, not a monorepo: `vcare-identity-api`, `vcare-care-api`, and
this hub. Work in one service constantly needs cross-service context — the other service's contract,
who owns which data, who calls whom, and the PRD — and an AI agent (or a human) should not have to
clone every repo to get it. Options: docs only in each repo (no whole-system view), a hand-maintained
central docs repo (drifts immediately), or a central repo populated by automation.

## Decision
**Docs live in each service repo (source of truth). The hub aggregates the cross-cutting subset via
sync** — service card + OpenAPI contract per spoke — plus the platform-level documents that belong to
no single service: the PRD, landscape, data-ownership map, platform ADRs, and glossary.

- **Spokes own the development workflow**: each has its own `.claude/` (commands, agents, skills,
  settings), `CLAUDE.md`, `docs/`, and `contracts/openapi.yaml`.
- **The hub has no `.claude/`** — it runs no workflow; it only aggregates.
- `catalog/<service>.card.md` and `contracts/<service>.openapi.yaml` are written only by
  `scripts/sync-from-spoke.sh` and never hand-edited; the spoke wins on disagreement.
- A spoke's **`/system-design`** updates hub `architecture/landscape.md`,
  `architecture/data-ownership.md`, `glossary.md`, and hub ADRs when a topic is cross-service.
- Agents follow a retrieval escalation: local grep → hub INDEX → hub content → sibling repo on disk
  (ask the user if unsure it is checked out) → GitHub MCP peek → clone only to change or run. See the
  hub [CLAUDE.md](../CLAUDE.md).

## Consequences
- ➕ One place to understand the system; per-service docs stay truthful next to their code.
- ➕ Cheap for agents: read the hub, don't clone the fleet.
- ➕ Each spoke can build against the other's synced contract (Care's Identity fake is built from
  `contracts/identity-service.openapi.yaml`).
- ➕ Drift is detectable: synced copies can be diffed against their source and `last_verified` is
  checked by `scripts/check-freshness.sh`.
- ➖ Requires running the sync and a metadata convention (frontmatter with `sync_to_hub`, a SYNCED
  header on copies). Running it from spoke CI is deferred, so today a stale sync is possible.
- ➖ Platform documents edited from a spoke's `/system-design` cross repo boundaries and need review
  in the hub.
- ➖ A semantic-search layer (docs MCP) is deferred — `INDEX.md` is the router until volume forces it.

## Alternatives considered
- **Per-repo docs only** — no whole-system view and no home for the PRD; agents must clone
  everything. Rejected.
- **Hand-maintained docs repo** — guaranteed drift between contracts and their copies. Rejected.
- **Monorepo** — rejected by the setup design: the services are independently deployable with
  separate owners, and a monorepo would blur the boundary ADR 0001 draws.
