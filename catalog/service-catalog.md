---
title: Service Catalog
owner: platform-team
service: platform
status: stable
diataxis: reference
last_verified: 2026-09-14
tags: [catalog, services, ownership]
related: [landscape, data-ownership]
---

# Service Catalog

Every service on the vcare platform. One row per service; details live in each service's card
(synced from its repo). This table is the entry point for "what exists and who owns it".

| Service | Repo | Owner | Tier | Status | Card |
|---|---|---|---|---|---|
| identity-service | `vcare-identity-api` | identity-team | 1 (sync, critical path — nobody logs in without it) | design — no code yet | [card](./identity-service.card.md) |
| care-service | `vcare-care-api` | care-team | 1 (sync, critical path — search, booking, consultations) | design — no code yet | [card](./care-service.card.md) |
| ai-retrieval-service | not created | not assigned | Phase 2 | planned — not built (PRD §12) | no card |

## Tiers
- **Tier 1** — in the synchronous critical path; an outage is a platform outage (or, for Identity,
  a login outage for every user).
- **Tier 2** — asynchronous or best-effort; degrades gracefully and retries. No Tier 2 service
  exists yet.

## Adding a service
1. In the new service repo: create `docs/service-card.md` with frontmatter `sync_to_hub:
   catalog/<service>.card.md`, and `contracts/openapi.yaml` as the source of truth for its API.
2. Run the hub sync: `scripts/sync-from-spoke.sh <service> ../<repo>`
   (see [scripts/sync-from-spoke.sh](../scripts/sync-from-spoke.sh)).
3. Add a row here.
4. Add a node and its calls to [architecture/landscape.md](../architecture/landscape.md).
5. Add its owned data to [architecture/data-ownership.md](../architecture/data-ownership.md).
6. If it calls another service's `/internal/*` routes: register a **service client** in Identity with
   its allowed **scopes**, and have the provider define any new scope in its contract first.
