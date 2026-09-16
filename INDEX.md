---
title: vcare Docs Hub — Index
owner: platform-team
service: platform
status: stable
last_verified: 2026-09-15
tags: [index, router, hub, platform]
related: [prd, service-catalog, overview, deployment, capacity, landscape, glossary]
---

# vcare Documentation Hub — Index

**Read this first.** The router for the whole system. Find where an answer lives, then open that
one doc. Platform-scope answers live here; a service's internals live in its repo
([ADR 0008](./adr/0008-doc-placement-by-scope.md)). For how retrieval escalates (hub → sibling on disk →
GitHub MCP → clone), see [CLAUDE.md](./CLAUDE.md).

## Source of intent
| Doc | Read it when you need to… |
|---|---|
| [product/prd.md](./product/prd.md) | the PRD: what the platform must do and why; every service's scope traces back here |

## Understand the system
| Doc | Read it when you need to… |
|---|---|
| [architecture/overview.md](./architecture/overview.md) | see the whole platform: C4 context and containers, services at a glance, principles, shared technical baseline |
| [architecture/deployment.md](./architecture/deployment.md) | see how the platform runs: edge routing, networks, every service's runtime components, availability and DR, release pipeline, observability |
| [architecture/capacity.md](./architecture/capacity.md) | check the load the platform is sized for, cross-service load, and each service's sizing headlines |
| [architecture/landscape.md](./architecture/landscape.md) | see how services talk: dependency graph, service-to-service auth, the three integration cases with their failure policies |
| [architecture/data-ownership.md](./architecture/data-ownership.md) | know which service is the single writer of which data |
| [glossary.md](./glossary.md) | agree on what a term means ("slot", "verification", "account status", "hydration", "platform scope") |

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
| [adr/0005-single-origin-edge-routing.md](./adr/0005-single-origin-edge-routing.md) | web app and both APIs share one origin; the edge routes by path prefix; no CORS in production |
| [adr/0006-doctor-account-status-via-care-only.md](./adr/0006-doctor-account-status-via-care-only.md) | only Care initiates a doctor's account-status change; Identity's admin route refuses doctor targets |
| [adr/0007-managed-container-platform.md](./adr/0007-managed-container-platform.md) | services run as containers on a managed container platform (reference: AWS ECS on Fargate) |
| [adr/0008-doc-placement-by-scope.md](./adr/0008-doc-placement-by-scope.md) | platform-scope docs live only in the hub, service-scope docs only in the service; split topics use a roll-up |
| [adr/0009-doctor-reinstatement-via-care.md](./adr/0009-doctor-reinstatement-via-care.md) | Care initiates doctor reinstatement (Case 4, retry-report-pending); Identity's internal route allows `suspended → active` |
| [adr/0011-object-storage-host.md](./adr/0011-object-storage-host.md) | browsers reach a service's private bucket directly with presigned URLs — the one exception to the single origin; bucket CORS `POST` from the web origin only |
| [adr/0010-notification-contact-lookup.md](./adr/0010-notification-contact-lookup.md) | Care's worker resolves notification emails via Identity `GET /internal/users/contacts` (scope `users:contact:read`); never stored |

## Design history
| Doc | Read it when you need to… |
|---|---|
| [docs/superpowers/specs/2026-09-14-vcare-ai-setup-design.md](./docs/superpowers/specs/2026-09-14-vcare-ai-setup-design.md) | understand how the three repos and their AI setup were designed |
| [docs/superpowers/plans/2026-09-14-vcare-ai-setup.md](./docs/superpowers/plans/2026-09-14-vcare-ai-setup.md) | see the implementation plan that produced the setup |

## Freshness
Every doc carries `last_verified`. Run `scripts/check-freshness.sh` to flag stale/unstamped docs.
Wiring this (plus link, contract-drift, and placement checks) into CI is deferred — see [TODO.md](./TODO.md).
