---
title: vcare Platform Deployment Topology
owner: platform-team
service: platform
status: accepted
diataxis: explanation
last_verified: 2026-09-15
tags: [architecture, deployment, topology, devops, networking, slo, disaster-recovery, release, observability]
related: [overview, capacity, landscape, adr-0001-two-service-split, adr-0005-single-origin-edge-routing, adr-0007-managed-container-platform, adr-0008-doc-placement-by-scope]
---

# Platform Deployment Topology

How the whole platform runs: edge, networks, every service's runtime components, availability targets, the
release pipeline, and observability. Platform-scope (hub [ADR 0008](../adr/0008-doc-placement-by-scope.md)).
Each service's scaling rules, bottlenecks, metrics, and alerts live in its repo — see "Per-service runtime
detail". Decisions: [ADR 0005](../adr/0005-single-origin-edge-routing.md) (edge),
[ADR 0007](../adr/0007-managed-container-platform.md) (managed containers). Sizing: [capacity.md](./capacity.md).

## 1. Topology
```
 Browser ──HTTPS──▶ Edge: CDN + WAF   https://vcare.example                            (ADR 0005)
                     ├─ /                                          → static web app (object storage)
                     ├─ /api/auth/*  /api/users/*  /.well-known/*  → public LB → identity-api :3000
                     ├─ every other /api/*                         → public LB → care-api     :3001
                     └─ /internal/*, /api/health/*                 → never routed (404 at the edge)

 private network — one region, ≥ 2 availability zones
 ─────────────────────────────────────────────────────────────────────────────────────────────────
  identity-service                                   care-service
   identity-api     ×2..6  (:3000, :3100)             care-api     ×2..6  (:3001, :3101)
   identity-worker  ×1     outbox, purges             care-worker  ×1     sync retrier, outbox, reminders
   identity-migrate        one-off per release        care-migrate        one-off per release
      ├─▶ PostgreSQL (identity), Multi-AZ, PITR           ├─▶ PostgreSQL (care), primary + async replica, PITR
      └─▶ Redis (identity) — Tier 2                       ├─▶ Redis (care)
                                                          └─▶ object storage (private bucket)

  care-api ──service token──▶ internal LB ──▶ identity-api :3100  /internal/*     (Cases 1, 2, 3)
  care-api ──JWKS fetch─────▶ identity-api /.well-known/jwks.json (cached)
  admin tooling / future service clients ──▶ internal LB ──▶ care-api :3101  /internal/doctors/*

  care-worker ──service token──▶ internal LB ──▶ identity-api :3100  /internal/users/contacts (ADR 0010)
  egress:   identity-worker → email provider · care-worker → email provider, object storage (quarantine purge) · care-api → video room provider, object storage
  browser:  presigned POST / GET straight to care-service's private bucket (ADR 0011) — never through the edge or an API
  secrets:  managed secrets store → each service's own secrets (never shared)
  logs:     stdout JSON + embedded metrics → platform log service → alerts
 ─────────────────────────────────────────────────────────────────────────────────────────────────
  identity and care snapshots ──copy──▶ second region (DR only)
```

**Reference implementation** (ADR 0007): ECS on Fargate, CloudFront + WAF, public ALBs and internal ALBs or Service
Connect, RDS PostgreSQL Multi-AZ, ElastiCache Redis, S3, Secrets Manager, CloudWatch — all as infrastructure as code.

## 2. Edge routing
Summary of [ADR 0005](../adr/0005-single-origin-edge-routing.md); the ADR table is authoritative.

| Path prefix | Target |
|---|---|
| `/api/auth/*`, `/api/users/*`, `/.well-known/*` | identity-service public listener |
| any other `/api/*` | care-service public listener |
| `/api/health/*`, `/internal/*` | not routed (`404`); load balancers probe health directly |
| everything else | static web app |

Prefixes never overlap. A service adding a top-level public prefix changes the edge table (IaC) and ADR 0005 in the
same release. CORS is disabled in production. WAF rate-based and bot rules protect `/api/auth/login`,
`/api/auth/register/*`, and `/api/auth/forgot-password`.

## 3. Runtime components and network rules

| Component | Service | Image / entrypoint | Count | Egress | Reaches |
|---|---|---|---|---|---|
| `identity-api` | identity-service | one image, both listeners | min 2, max 6, across AZs | **none** | own Postgres, own Redis |
| `identity-worker` | identity-service | same image, worker entrypoint | 1 | email provider | own Postgres |
| `identity-migrate` | identity-service | same image, migrate entrypoint | one-off per release | none | own Postgres |
| `care-api` | care-service | one image, both listeners | min 2, max 6, across AZs | video provider, object storage | own Postgres, own Redis, Identity internal LB and JWKS |
| `care-worker` | care-service | same image, worker entrypoint | 1 | email provider | own Postgres, own Redis, Identity internal LB |
| `care-migrate` | care-service | same image, migrate entrypoint | one-off per release | none | own Postgres |

**Network rules (every service):**
- The public load balancer exposes only the public port; the internal port is reachable only through a private load
  balancer or service discovery.
- Security groups on an internal port admit **registered service clients only** (today: care-api and care-worker → identity-api
  `:3100`; admin tooling and future clients → care-api `:3101`). Identity makes no calls to Care.
- A service's PostgreSQL and Redis accept only that service's task security groups — never another service's
  ([ADR 0001](../adr/0001-two-service-split.md)).
- Outbound internet egress is granted per component, only to the providers listed above.
- **Object storage is the one browser-facing host outside the single origin** ([ADR 0011](../adr/0011-object-storage-host.md)).
  Each bucket belongs to one service and is private (Block Public Access on, TLS-only policy, server-side
  encryption); browsers use only presigned URLs issued after authorization; bucket CORS allows `POST` from the web
  origin only; the web app's CSP lists the bucket host in `form-action`/`connect-src`. Today: care-service's bucket
  (verification documents, record attachments — care ADRs 0013–0014).

## 4. Availability and recovery
Platform availability is bounded by its weakest Tier-1 service. Values here are **roll-ups**: each is authored in
the service's decision record and linked.

| Service | Tier | Availability | RPO | RTO | Mechanisms | Source |
|---|---|---|---|---|---|---|
| identity-service | 1 | **99.95 %** monthly | 0 (AZ) · ≤ 5 min (corruption) | ≤ 5 min (task/AZ) · ≤ 4 h (region) | ≥ 2 tasks in ≥ 2 AZs; sync standby; PITR; daily snapshots 35 d copied cross-region; quarterly drills | [identity ADR 0009](../../vcare-identity-api/docs/adr/0009-availability-and-recovery-targets.md) |
| care-service | 1 | **99.9 %** monthly | ≤ 1 min (AZ) · ≤ 5 min (corruption) | ≤ 30 min (task/AZ, replica promotion) · ≤ 4 h (region) | ≥ 2 tasks in ≥ 2 AZs; single-AZ primary + async replica; PITR; daily snapshots 35 d copied cross-region; quarterly drills | [care ADR 0005](../../vcare-care-api/docs/adr/0005-availability-and-recovery-targets.md) |

**Platform availability: 99.9 %** — bounded by care-service, the weaker Tier-1 service. Raising it requires a
synchronous standby for Care (superseding care ADR 0005).

**Dependency tiers.** In both services Redis and the email provider are Tier 2: a loss degrades caches, rate
limiting, idempotency, and email timing, never login or booking (identity ADR 0008; care ADR 0006). Health is split
into liveness and readiness in both (identity ADR 0014; care ADR 0006). Worker components are Tier 2 (delays only).
A Case-2 Identity outage never fails Care requests; a Case-3 outage returns `503` for suspensions only
([landscape.md](./landscape.md)).

## 5. Release pipeline (every service)
1. **CI:** typecheck, lint, unit + integration tests (real Postgres and Redis), contract conformance, image build,
   image scan.
2. **Push** one immutable image, tag = commit SHA.
3. **Migrate** as a one-off task before rollout. Migrations follow **expand → migrate → contract**: every migration
   works with both the running and the new code; destructive steps ship in a later release.
4. **Rolling deploy** with minimum healthy 100 %, maximum 200 %; background components after API tasks.
5. **Post-deploy smoke** checks defined by the service (e.g. identity: JWKS non-empty, readiness, synthetic login).
6. **Rollback** = redeploy the previous task definition; the schema stays compatible by step 3.

**Cross-service ordering.** A change to an `/internal/*` shape ships **provider first**, keeps the old shape until the
consumer has shipped, then removes it ([landscape.md](./landscape.md) → Internal API surface). A new public prefix
ships with its edge-table change.

## 6. Observability across services
| Signal | Platform rule | Source |
|---|---|---|
| Logs | structured JSON to stdout, one line per event, `service` field, PII/clinical redaction | each spoke `CLAUDE.md` → Privacy and logging |
| Trace | `X-Request-Id` accepted or generated at the first service, forwarded on every internal call, persisted on status-change and audit rows | [glossary](../glossary.md) → Request id |
| Metrics | derived from logs in the platform's embedded metric format; no tracing SDK in MVP; OpenTelemetry is a future **joint** Identity + Care ADR | identity ADR 0013, care ADR 0007 |
| Health | load balancers use readiness; orchestrator restarts on liveness; health is never routed by the edge | identity ADR 0014, care ADR 0006 |
| Alerts | per service, with runbook actions | each service's `docs/runbook.md` |

## 7. Per-service runtime detail
Service scope — scaling triggers, health wiring, bottlenecks with mitigations, metrics and alerts, configuration.

| Service | Doc |
|---|---|
| identity-service | [`vcare-identity-api/docs/architecture/deployment.md`](../../vcare-identity-api/docs/architecture/deployment.md) |
| care-service | [`vcare-care-api/docs/architecture/deployment.md`](../../vcare-care-api/docs/architecture/deployment.md) (components, availability, release smoke, bottlenecks, metrics, alerts) |

## 8. Deferred (platform)
Multi-region active-passive (only worth it when every Tier-1 service goes multi-region) · Kubernetes (revisit with
Phase 2 and more services, superseding ADR 0007) · OpenTelemetry traces (joint ADR) · a docs/IaC check that the edge
routing table matches ADR 0005.
