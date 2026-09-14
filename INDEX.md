---
title: vcare Docs Hub — Index
owner: platform-team
service: platform
status: stable
last_verified: 2026-09-14
tags: [index, router, hub, platform]
related: [prd, service-catalog, landscape, glossary]
---

# vcare Documentation Hub — Index

**Read this first.** The router for the whole system. Find where an answer lives, then open that
one doc. For how retrieval should escalate (hub → sibling on disk → GitHub MCP → clone), see
[CLAUDE.md](./CLAUDE.md).

## Source of intent
| Doc | Read it when you need to… |
|---|---|
| [product/prd.md](./product/prd.md) | the PRD: what the platform must do and why; every service's scope traces back here |

## Understand the system
| Doc | Read it when you need to… |
|---|---|
| [architecture/landscape.md](./architecture/landscape.md) | see both services, how they talk, service-to-service auth, and the three integration cases with their failure policies |
| [architecture/data-ownership.md](./architecture/data-ownership.md) | know which service is the single writer of which data |
| [glossary.md](./glossary.md) | agree on what a term means ("slot", "verification", "account status", "hydration") |

## Find a service
| Doc | Read it when you need to… |
|---|---|
| [catalog/service-catalog.md](./catalog/service-catalog.md) | list every service, owner, repo, tier, status |
| [catalog/identity-service.card.md](./catalog/identity-service.card.md) | Identity & Access: accounts, auth, tokens, sessions, account status (synced) |
| [catalog/care-service.card.md](./catalog/care-service.card.md) | Care: doctors, verification, schedules, consultations, records, help, audit (synced) |

## Look up a contract (source of truth, synced from spokes)
| Contract | Service |
|---|---|
| [contracts/identity-service.openapi.yaml](./contracts/identity-service.openapi.yaml) | identity-service HTTP API (public + `/internal/*` + JWKS) |
| [contracts/care-service.openapi.yaml](./contracts/care-service.openapi.yaml) | care-service HTTP API (public + `/internal/*`) |

No event contracts exist: MVP is HTTP-only (see [TODO.md](./TODO.md)).

## Decisions
| ADR | Decision |
|---|---|
| [adr/0001-two-service-split.md](./adr/0001-two-service-split.md) | Identity and Care are two independently deployable services with separate databases |
| [adr/0002-hub-and-spoke-docs.md](./adr/0002-hub-and-spoke-docs.md) | docs live in the spokes; this hub aggregates the cross-cutting subset via sync |
| [adr/0003-service-token-s2s-auth.md](./adr/0003-service-token-s2s-auth.md) | services authenticate to each other with short-lived scoped client-credentials JWTs |
| [adr/0004-numeric-ids-exposed.md](./adr/0004-numeric-ids-exposed.md) | `BIGSERIAL` ids are exposed on the wire, with enumeration mitigations |

## Design history
| Doc | Read it when you need to… |
|---|---|
| [docs/superpowers/specs/2026-09-14-vcare-ai-setup-design.md](./docs/superpowers/specs/2026-09-14-vcare-ai-setup-design.md) | understand how the three repos and their AI setup were designed |
| [docs/superpowers/plans/2026-09-14-vcare-ai-setup.md](./docs/superpowers/plans/2026-09-14-vcare-ai-setup.md) | see the implementation plan that produced the setup |

## Freshness
Every doc carries `last_verified`. Run `scripts/check-freshness.sh` to flag stale/unstamped docs.
Wiring this (plus link + contract-drift checks) into CI is deferred — see [TODO.md](./TODO.md).
