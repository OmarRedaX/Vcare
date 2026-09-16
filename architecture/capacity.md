---
title: vcare Platform Capacity Model
owner: platform-team
service: platform
status: accepted
diataxis: explanation
last_verified: 2026-09-15
tags: [architecture, capacity, sizing, load, scale, platform]
related: [overview, deployment, landscape, prd, adr-0008-doc-placement-by-scope]
---

# Platform Capacity Model

The load the whole platform is designed for, the cross-service load it implies, and a roll-up of every service's
sizing. Platform-scope (hub [ADR 0008](../adr/0008-doc-placement-by-scope.md)).

- **Authored here:** the shared traffic assumptions (section 1) and the cross-service load (section 2). Change them
  only through `/system-design`; every service then re-derives.
- **Authored in each service:** its per-endpoint load, compute, database, per-table storage, and its own 10× check.
  Section 3 quotes only the headlines and links to the derivation; a service that changes a headline updates its row
  here in the same session.

Baseline chosen in identity-service `/system-design` on 2026-09-15 (its decision D12). PRD §11 sets the performance
targets it must hold: search < 400 ms, two-week slot computation < 300 ms.

## 1. Shared traffic assumptions

| Input | Value | Rationale |
|---|---|---|
| Registered users | **500 k** (≈ 2.5 k doctors) | lean MVP launch-to-growth target |
| Daily active users (DAU) | **10 % = 50 k** | visit-driven health booking, not a daily-habit app |
| New accounts | ≈ 900/day | 500 k over ~18 months |
| Listing pages per DAU per day (search, consultation lists, patient lists) | 10 → **500 k/day** | drives Care's hot read path and Case-2 hydration |
| Peak hour | **15 %** of daily traffic, **×2** burst inside the hour | evening booking peak |
| Campaign spike | ×5 normal login peak | marketing pushes |
| Hostile traffic design point | **~500 login attempts/s** | credential stuffing does not scale with the user base |
| Design headroom | must hold at **10×** (5 M registered / 500 k DAU) without redesign | growth without re-architecture |

Peak rps = daily count × 0.15 / 3600 × 2.

## 2. Cross-service load

| Flow | Per day | Peak rps | Notes |
|---|---|---|---|
| Case 2 — hydration lookups in Care | 500 k | — | one per listing page (batched ids) |
| Case 2 — calls reaching Identity `GET /internal/users` | **~100 k** (Care cache hit ≈ 80 %, TTL 300 s) | **~9** (20–50 ids each) | one `id = ANY($1)` PK query per call |
| JWKS fetches by Care | negligible | < 1 | cached 300 s; refetch on unknown `kid` at most once per minute |
| Service-token exchanges | ~1 per 270 s per Care task | < 1 | one argon2id verify each |
| Cases 1 and 3 — status changes | < 100 | < 1 | doctor verification decisions and suspensions |

At 10×: ~1 M hydration calls/day reach Identity (~90 rps) — still PK lookups, still inside Identity's
`/internal/users` budget (p95 < 50 ms).

## 3. Per-service sizing roll-up

| Service | Legit peak | Compute | PostgreSQL | Storage (steady / provisioned) | Redis | 10× verdict | Derivation |
|---|---|---|---|---|---|---|---|
| identity-service | ~40–50 rps (refresh-dominated); login ~5/s at campaign peak | `identity-api` 2 × (1 vCPU, 2 GB), autoscale to 6; `identity-worker` 1 × (0.5 vCPU, 1 GB) | 2 vCPU / 8 GB class, Multi-AZ; ~100 qps, ~30 writes/s, ~27 connections | ≈ 7 GB / 50 GB with autoscaling | smallest managed node with a replica (< 256 MB) | holds with scale-out; `refresh_tokens` needs monthly partitioning (new ADR) | [`vcare-identity-api/docs/architecture/capacity.md`](../../vcare-identity-api/docs/architecture/capacity.md) |
| care-service | ≈ 105 rps (search 25, slots 25, lists 17); bookings 7.5 k/day (0.6/s) | `care-api` 2 × (1 vCPU, 2 GB), autoscale to 6; `care-worker` 1 × (0.5 vCPU, 1 GB) | 2 vCPU / 8 GB class, primary + async replica; ≈ 400 qps, ≈ 10 writes/s, ≈ 25 connections | ≈ 52 GB / 100 GB with autoscaling (audit 36 GB/yr); object storage ≈ 2 TB/yr | smallest managed node with a replica (< 100 MB) | holds with scale-out (≈ 15–20 API tasks, connection proxy, replica reads) | [`vcare-care-api/docs/architecture/capacity.md`](../../vcare-care-api/docs/architecture/capacity.md) |

Care's consultation volume (7.5 k/day) is a Care-authored assumption in its derivation, not a platform input.

## 4. Platform revisit triggers
Re-run this model when any of these holds for a week: DAU > 150 k · registered users > 1.5 M · hydration calls
reaching Identity > 300 k/day. Each service's own triggers (table sizes, latency, CPU) are in its derivation doc.
