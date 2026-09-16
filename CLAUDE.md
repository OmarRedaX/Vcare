# CLAUDE.md — vcare Documentation Hub

This repo is the **documentation hub** for the vcare Virtual Care Platform. It does **not** contain
application code. It holds every **platform-scope** doc — the ones true of the whole system or of more than one
service — plus synced copies of each service's card and contract, so that a human or an AI agent can understand
the whole system from one place without cloning every service.

**There is no `.claude/` directory here, by design.** The spokes own the development workflow
(commands, agents, skills, settings); the hub only holds platform docs and aggregates. Do not add one.

## The hub-and-spoke model

```
   spoke repos (service scope)                     this hub (platform scope)
 ┌──────────────────────────────┐    sync     ┌──────────────────────────────────────┐
 │ vcare-identity-api           │ ──────────▶ │ product/prd.md (source of intent)    │
 │   (identity-service)         │  card +     │ catalog/  (service cards, synced)    │
 │   docs/, contracts/          │  openapi    │ contracts/ (OpenAPI, synced)         │
 ├──────────────────────────────┤             │ architecture/ overview, deployment,  │
 │ vcare-care-api               │ ──────────▶ │   capacity, landscape, data-ownership│
 │   (care-service)             │             │ adr/  glossary.md  INDEX.md          │
 │   docs/, contracts/          │             └──────────────────────────────────────┘
 └──────────────────────────────┘
        ▲        spokes read the hub at ../vcare-hub;          │
        └──── their /system-design writes platform docs here ──┘
```

**Source-of-truth rule:** service-scope docs live **in the service repo**, next to the code, so they stay truthful.
Platform-scope docs live **only here**. Synced files (`catalog/*.card.md`, `contracts/*`) are populated by
`scripts/sync-from-spoke.sh` and are **never hand-edited**. If a card or contract here disagrees with the spoke,
**the spoke wins** and the sync is stale — re-run it.

## Doc placement — hub or service (binding)

Every doc and every fact has **one home, decided by scope** — not by the repo the work happened in
([ADR 0008](./adr/0008-doc-placement-by-scope.md)). Step-by-step procedure: the `docs-placement` skill in each
spoke.

**Scope test.** Ask: *whose code makes this true, and who must agree on it?* If the answer is one service, the
doc belongs to that service. If it is several services, the edge, the platform infrastructure, or anyone who
shouldn't need to read one service's code, the doc belongs here.

| Lives in the hub (platform scope) | Lives in the service repo (service scope) |
|---|---|
| PRD, NFRs | module docs (brainstorm, spec, tasks, QA, reviews) |
| system context, platform container view, services at a glance, shared technical baseline → `architecture/overview.md` | module map, layering, request pipeline, the service's own container view → `docs/architecture/overview.md` |
| edge routing, network zones, every service's runtime components, availability/DR roll-up, release pipeline, observability rules → `architecture/deployment.md` | the service's scaling triggers, health wiring, bottlenecks, metrics, alerts, config → `docs/architecture/deployment.md` / `infrastructure.md` |
| shared traffic assumptions, cross-service load, per-service sizing roll-up → `architecture/capacity.md` | the service's per-endpoint load, compute, per-table storage, its 10× check → `docs/architecture/capacity.md` |
| dependency graph, service auth, integration cases and failure policies, internal API surface → `architecture/landscape.md` | the consumer or provider implementation of a case (client, retry jobs, alerts) |
| single writer per data domain → `architecture/data-ownership.md` | tables, constraints, indexes → `docs/architecture/data-model.md` |
| shared terms → `glossary.md`; platform-wide decisions → `adr/` | endpoint prose, runbook, quickstart, service decisions → `docs/adr/` |
| service list and tiers → `catalog/service-catalog.md` | service card + OpenAPI contract (authored in the spoke, synced here) |

**Split topics (roll-up pattern).** Capacity, deployment, availability, observability, and data ownership each have
a platform part and a service part. The hub doc carries the platform part plus **one row per service** with
headline values and a link to the service doc; the service doc carries the derivation. **Each number is authored
once** — inputs here, derived values in the service; a quote always links to where the value is authored. A change
to a headline updates both sides in the same session.

**Frontmatter marks scope.** Every hub `architecture/` and `adr/` doc has `service: platform` (and
`owner: platform-team`); no spoke doc ever does. The spokes' Stop hook blocks both violations.

**Misplaced doc found?** Move it (don't copy), split it if it has both scopes, fix every link, and bump
`last_verified`.

## When to read the hub vs a service
| You need… | Read |
|---|---|
| the whole system, a new service's starting point | `INDEX.md` → `architecture/overview.md` |
| how services talk, authenticate, fail | `architecture/landscape.md` |
| how anything is deployed, routed, or recovered | `architecture/deployment.md` |
| what load the platform is sized for | `architecture/capacity.md` |
| who owns data, what a term means, why a platform decision | `architecture/data-ownership.md`, `glossary.md`, `adr/` |
| another service's API | `contracts/<service>.openapi.yaml` (synced) |
| how one service implements something internally | that service's repo (escalation below) — not the hub |

## How an agent should retrieve docs (escalation — cheapest first)

Do **not** clone repos to read them. Escalate only when the cheaper step didn't answer it:

1. **Current service** — if you're working in a service repo and the question is service-scope, grep it locally.
2. **Hub `INDEX.md`** — the router. Where does the answer live?
3. **Hub content** — every platform-scope question (overview, deployment, capacity, a contract, who-owns-what,
   who-calls-whom, what the PRD requires) is answered *here*. Stop.
4. **Sibling repo checked out locally?** If you need a service-scope detail of *another* service, first check
   whether that service's repo is present next to this one (`../vcare-identity-api`, `../vcare-care-api`). If it
   is, read its docs **directly on disk**. **If you're not sure whether it's checked out, ASK the user** ("Is
   `<service>` cloned locally?") before reaching out — don't assume it isn't.
5. **GitHub MCP peek** — only if the repo is **not** local, read the specific file live via GitHub
   MCP. Still no clone.
6. **Clone** — only when you are going to actually **change or run** that other service.

## What lives here
| Path | What |
|---|---|
| `INDEX.md` | top-level router across all services — READ FIRST |
| `product/prd.md` | the PRD — **source of intent**; every service's scope traces back here |
| `architecture/overview.md` | platform architecture overview: C4 L1/L2, services at a glance, principles, shared technical baseline |
| `architecture/deployment.md` | platform deployment topology: edge, networks, runtime components, availability roll-up, release pipeline, observability |
| `architecture/capacity.md` | platform capacity model: shared traffic assumptions, cross-service load, per-service sizing roll-up |
| `architecture/landscape.md` | integration seams: dependency graph, service auth, the three integration cases, internal API surface |
| `architecture/data-ownership.md` | platform data-ownership map (single writer per data domain) |
| `catalog/` | service catalog + one card per service (cards synced) |
| `contracts/` | synced OpenAPI from each spoke (`<service>.openapi.yaml`) |
| `adr/` | platform-level architecture decisions |
| `glossary.md` | ubiquitous language — shared terms, defined once |
| `scripts/` | `sync-from-spoke.sh` (aggregate a spoke) + `check-freshness.sh` (drift check, run manually) |
| `TODO.md` | deferred: pending Care roll-up rows, docs-lint CI, CI-triggered sync, events/AsyncAPI, docs-MCP search |
| `docs/superpowers/` | design history — the setup design spec and its implementation plan |

## Who may edit what
| Hub path | Edited by | How |
|---|---|---|
| `architecture/overview.md` | a spoke's `/system-design` when a service, container, external system, or shared baseline changes | direct edit; set `last_verified` |
| `architecture/deployment.md` | a spoke's `/system-design` for routing, networking, runtime components, availability, release, observability | direct edit; update that service's roll-up rows; set `last_verified` |
| `architecture/capacity.md` | a spoke's `/system-design` for traffic assumptions, cross-service load, or its sizing headlines | direct edit; changing an assumption means every service re-derives; set `last_verified` |
| `architecture/landscape.md` | a spoke's `/system-design` for a cross-service topic | direct edit; set `last_verified` |
| `architecture/data-ownership.md` | a spoke's `/system-design` for a cross-service topic | direct edit; set `last_verified` |
| `adr/` | a spoke's `/system-design` when the decision is platform-wide | new append-only ADR; supersede, never rewrite |
| `glossary.md` | a spoke's `/system-design` when a shared term is introduced or sharpened | add the term before it spreads |
| `catalog/*.card.md`, `contracts/*` | **nobody by hand** | only `scripts/sync-from-spoke.sh` |
| `catalog/service-catalog.md` | platform-team when a service is added or changes tier/status | direct edit |
| `product/prd.md` | product owner | direct edit; scope changes flow from here into the spokes |

## Spokes own the dev workflow
Each spoke runs the full per-module workflow (`/system-design → /brainstorm → /construct-spec →
/develop → /write-tests → /manual-qa → /review-code → /update-docs`) with its own `.claude/`
commands, agents, and skills. The hub does **not** run that workflow. Only `/system-design` writes platform docs
here; every other phase writes service docs and lists platform deltas. Drift prevention in CI
(freshness/link/contract-drift checks) is deferred — see `TODO.md`; the spokes' Stop hook covers freshness,
retired terms, card/contract drift, and placement today.
