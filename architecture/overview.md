---
title: vcare Platform Architecture Overview
owner: platform-team
service: platform
status: stable
diataxis: explanation
last_verified: 2026-09-15
tags: [architecture, overview, c4, platform, services, baseline]
related: [prd, landscape, deployment, capacity, data-ownership, service-catalog, glossary, adr-0001-two-service-split, adr-0005-single-origin-edge-routing, adr-0007-managed-container-platform, adr-0008-doc-placement-by-scope]
---

# vcare Platform Architecture Overview

**Start here for the whole system.** What the platform is made of, how the pieces relate, and the technical
baseline every service shares. Intent comes from [the PRD](../product/prd.md) (§4, §5, §11). This is a
platform-scope doc (hub [ADR 0008](../adr/0008-doc-placement-by-scope.md)): each service's internals — modules,
layering, request pipeline — live in that service's repo.

| Question | Doc |
|---|---|
| How do the services talk, authenticate, and fail? | [landscape.md](./landscape.md) |
| How is the platform deployed, and what are the availability targets? | [deployment.md](./deployment.md) |
| What load is the platform sized for? | [capacity.md](./capacity.md) |
| Which service writes which data? | [data-ownership.md](./data-ownership.md) |

## C4 — Level 1: System context
```
  ┌──────────┐  ┌──────────┐  ┌──────────┐
  │ Patient  │  │  Doctor  │  │  Admin   │      (web clients)
  └────┬─────┘  └────┬─────┘  └────┬─────┘
       └─────────────┼─────────────┘
                     │ HTTPS (Bearer access token)
                     ▼
  ┌───────────────────────────────────────────────┐
  │               vcare platform                  │
  │     identity-service   +   care-service       │
  └───────┬──────────────────┬─────────────┬──────┘
          │ email            │ video rooms │ documents, attachments
          ▼                  ▼             ▼
  ┌──────────────┐  ┌──────────────────┐  ┌────────────────┐
  │ Email        │  │ Video room       │  │ Object storage │   (external)
  │ provider     │  │ provider         │  │                │
  └──────────────┘  └──────────────────┘  └────────────────┘

  Future (Phase 2): AI & Retrieval service — a third system inside the platform boundary.
```

## C4 — Level 2: Containers and communication
```
      edge: CDN + WAF, single origin (ADR 0005) — /api/auth, /api/users, /.well-known → Identity;
            other /api → Care; / → web app; never /internal or /api/health
          ┌───────────────────────────────┴───────────────────────────────┐
          ▼                                                               ▼
 ┌──────────────────────────────┐                          ┌──────────────────────────────┐
 │ identity-service             │                          │ care-service                 │
 │  public   :3000  /api/*      │ ◀── JWKS fetch ───────── │  public   :3001  /api/*      │
 │           /.well-known/jwks  │     (cached, refreshed   │                              │
 │  internal :3100  /internal/* │      on unknown kid)     │  internal :3101  /internal/* │
 │                              │ ◀── internal calls ───── │                              │
 │  identity-worker (outbox)    │     service token        │  care-worker: sync retrier,  │
 │                              │   (Cases 1–4, contacts)  │  outbox, reminders           │
 └──────┬───────────────┬───────┘                          └──┬─────────┬─────────┬───────┘
        ▼               ▼                                     ▼         ▼         ▼
 ┌────────────┐  ┌─────────────┐                  ┌──────────────┐ ┌────────┐ ┌────────────────┐
 │ PostgreSQL │  │ Redis       │                  │ PostgreSQL   │ │ Redis  │ │ Object storage │
 │ (identity) │  │ rate limit, │                  │ (care)       │ │ cache, │ │ documents,     │
 │            │  │ idempotency │                  │ + btree_gist │ │ limits,│ │ attachments    │
 └────────────┘  └─────────────┘                  └──────────────┘ │ idemp. │ └────────────────┘
                                                                   └────────┘
 Internal listeners (:3100, :3101) bind to the private network only; the edge never routes /internal.
```
Ports are the local defaults; in production each listener sits behind its own load balancer
([deployment.md](./deployment.md)).

## Services at a glance
| Service | Owns | Tier | Listeners | Data stores | Background work | Internals |
|---|---|---|---|---|---|---|
| identity-service | accounts, authentication, tokens, sessions, account status, service clients | 1 — nobody logs in without it | public `/api/auth/*`, `/api/users/*`, `/.well-known/jwks.json`; internal `/internal/*` | own PostgreSQL; own Redis (Tier 2) | `identity-worker`: transactional outbox (emails), purges | [`vcare-identity-api/docs/architecture/overview.md`](../../vcare-identity-api/docs/architecture/overview.md) |
| care-service | doctors, verification, schedules, consultations, patient profiles, medical records, help center, audit | 1 — search, booking, consultations | public every other `/api/*`; internal `/internal/doctors/*` | own PostgreSQL (`btree_gist`); own Redis (Tier 2); private object storage | `care-worker`: Identity-sync retrier, notification outbox, reminders, cache refresh (care ADR 0008) | [`vcare-care-api/docs/architecture/overview.md`](../../vcare-care-api/docs/architecture/overview.md) |
| ai-retrieval-service | complaint parsing, summaries, ICD-10 lookup, help assistant, booking agent | Phase 2 — not built | — | vector store, model providers (planned) | — | [landscape.md → Phase 2](./landscape.md#phase-2--ai--retrieval-placement) |

Registry with owners and status: [catalog/service-catalog.md](../catalog/service-catalog.md).

## Architectural principles
1. **Independent services, separate databases** ([ADR 0001](../adr/0001-two-service-split.md)). No service reads
   another's tables; one writer per piece of data ([data-ownership.md](./data-ownership.md)).
2. **Synchronous HTTP only in MVP.** No message bus; events are future ([TODO.md](../TODO.md)).
3. **Identity is a leaf.** It calls no other vcare service, so Care cannot drag it down.
4. **Authorization without a network call.** Services verify EdDSA user tokens locally against Identity's JWKS.
5. **Service-to-service auth is short-lived scoped tokens** ([ADR 0003](../adr/0003-service-token-s2s-auth.md)) —
   never a shared database, static key, or trusted identity header.
6. **Failure policy follows business consequence**, not transport: degrade, retry-and-report-pending, or
   must-not-degrade ([landscape.md](./landscape.md)).
7. **One public origin** with edge path routing; `/internal/*` is private-network only
   ([ADR 0005](../adr/0005-single-origin-edge-routing.md)).
8. **Managed containers, one immutable image per service** ([ADR 0007](../adr/0007-managed-container-platform.md)).

## Shared technical baseline
True in every vcare service. Each spoke's `CLAUDE.md` is binding and holds the full rules; this table is the
platform summary so a new service starts aligned.

| Concern | Platform-wide choice |
|---|---|
| Runtime | Node.js 24 LTS + TypeScript (`strict`), Express 5 |
| Data access | Knex over `pg`, raw-SQL migrations, no ORM; `TIMESTAMPTZ` in UTC; soft delete |
| IDs | `BIGSERIAL`, exposed as numeric ids ([ADR 0004](../adr/0004-numeric-ids-exposed.md)) |
| Listeners | public `/api/*` and internal `/internal/*` on separate ports in one process |
| Tokens | `jose`, EdDSA (Ed25519); Identity signs, everyone verifies locally |
| Authorization | deny-by-default `authorize(policy)` on every route: roles + ownership |
| Errors | one envelope `{ success: false, error: { code, message, details?, requestId } }`; PascalCase codes, stable forever |
| Tracing | `X-Request-Id` accepted or generated, echoed, logged, forwarded on every internal call |
| Lists | cursor-based keyset pagination, `limit` ≤ 100 |
| Writes | `Idempotency-Key` (UUID), 24 h replay window |
| Logs and metrics | structured JSON to stdout, PII/clinical redaction; metrics derived from logs (identity-service ADR 0013, care-service ADR 0007) |
| Health | `…/health/live` (process) and `…/health/ready` (database only; Redis is Tier 2 in both services) — identity ADR 0014, care ADR 0006 |
| Background work | a separate worker component per service (`identity-worker`, `care-worker`) with a transactional outbox |
| API source of truth | each service's `contracts/openapi.yaml`, synced to [`contracts/`](../contracts/) |
