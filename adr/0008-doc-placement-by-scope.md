---
title: "ADR 0008: Doc placement by scope — platform docs in the hub, service docs in the service"
owner: platform-team
service: platform
status: accepted
diataxis: explanation
date: 2026-09-15
last_verified: 2026-09-15
tags: [adr, decision, documentation, ai, hub-and-spoke]
related: [adr-0002-hub-and-spoke-docs, overview, deployment, capacity, landscape, data-ownership, glossary]
---

# ADR 0008 — Doc placement by scope

- **Status:** Accepted
- **Date:** 2026-09-15
- **Deciders:** platform-team

## Context
[ADR 0002](./0002-hub-and-spoke-docs.md) keeps per-service docs in the spokes and the "cross-cutting subset" in the
hub, but gives no test for what is cross-cutting. As a result the identity-service `/system-design` of 2026-09-15
wrote platform material into its own repo. That included the traffic assumptions every service is sized from, the
deployment topology (edge, private network, both services' components), and the release pipeline, all in
`docs/architecture/capacity.md` and `deployment.md`. Meanwhile the hub had no platform overview, deployment, or
capacity doc. care-service could not find those facts without reading Identity's repo. The hub could not answer
"how is the platform deployed?" or "what load is it sized for?". The next Care design session would have written a
second, divergent copy.

## Decision
1. **Every doc and fact has one home, decided by scope** — never by the repo the work happened in.
   - **Platform scope** is anything true of the platform as a whole or of two or more services, or that another
     service, ops, or product must agree on without reading one service's code. It lives **in the hub**.
   - **Service scope** is anything made true only by one service's code. It lives **in that service's `docs/`**.
2. **Hub platform docs:** `product/prd.md`; `architecture/overview.md` (new — system context, containers, services at
   a glance, shared baseline); `architecture/deployment.md` (new — edge, networks, every service's components,
   availability roll-up, release pipeline, observability); `architecture/capacity.md` (new — shared assumptions,
   cross-service load, sizing roll-up); `architecture/landscape.md` (integration seams; its C4 views moved to
   `overview.md`); `architecture/data-ownership.md`; `glossary.md`; `adr/`; `catalog/service-catalog.md`.
3. **Service docs** keep internals: module map, layering, request pipeline, data model, API prose, configuration,
   the service's capacity derivation, its runtime components, bottlenecks, metrics, alerts, runbook, quickstart,
   service ADRs, module docs.
4. **Split topics use a roll-up.** Capacity, deployment, availability, observability, and data ownership each have
   a platform part and a service part. The hub holds the platform part plus one row per service quoting headline
   values with a link. The service holds the derivation. Each number is authored once: inputs in the hub, derived
   values in the service. A service that changes a headline updates its hub row in the same session.
5. **Frontmatter marks scope.** `service: platform` if and only if the file lives in the hub. The spokes' Stop hook
   blocks two cases: a spoke doc with `service: platform`, and a hub `architecture/` or `adr/` doc without it.
6. **Who writes the hub.** Only a spoke's `/system-design` hand-edits hub docs; the sync script writes cards and
   contracts. Every other workflow phase writes service docs and **lists** platform deltas for `/system-design`.
7. **Where it is written down.** The procedure is the spokes' `docs-placement` skill. The binding summary is in each
   spoke's `CLAUDE.md` → "Doc placement — hub or service" and in the hub `CLAUDE.md`.

This refines ADR 0002; it does not supersede it.

## Consequences
- ➕ The hub answers whole-system questions (overview, deployment, capacity) from one place, for every service.
- ➕ One fact, one home: a second service designing the same topic updates the hub doc instead of forking it.
- ➕ A mechanical guard (frontmatter check) catches the most common misplacement.
- ➖ A `/system-design` session now writes to two repos, and hub edits need review in the hub.
- ➖ Roll-up rows must be kept in step with service derivations by discipline (same-session rule); only the
  frontmatter check is automated.
- ➖ Split topics need judgment; the placement table in the skill is the tie-breaker.

## Alternatives considered
- **All architecture docs in the hub** — service internals would drift away from the code that makes them true;
  contradicts ADR 0002. Rejected.
- **Platform docs stay in whichever spoke designed them, linked from the hub** — the status quo; invisible to the
  other service and duplicated the next time it designs the same topic. Rejected.
- **Sync platform docs from a spoke like service cards** — a platform doc has no single owning spoke to sync from.
  Rejected.
