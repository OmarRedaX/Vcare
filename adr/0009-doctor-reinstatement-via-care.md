---
title: "ADR 0009: Doctor reinstatement is initiated by care-service (Case 4)"
owner: platform-team
service: platform
status: accepted
diataxis: explanation
date: 2026-09-15
last_verified: 2026-09-15
tags: [adr, decision, account-status, cross-service, integration, reinstatement]
related: [landscape, data-ownership, adr-0006-doctor-account-status-via-care-only, adr-0003-service-token-s2s-auth]
---

# ADR 0009 — Doctor reinstatement is initiated by care-service (Case 4)

- **Status:** Accepted — amends the reinstatement clause of [ADR 0006](./0006-doctor-account-status-via-care-only.md)
- **Date:** 2026-09-15
- **Deciders:** platform-team, care-team (identity-team to confirm the provider change)

## Context
ADR 0006 made Care the only initiator of doctor account-status changes and left reinstatement with no API path:
Identity's admin route refuses doctor targets, and its internal status route refuses `suspended → active`. The only
path was a manual ops procedure touching two databases.

## Decision
- **Case 4:** an admin reinstates a doctor in Care (`PATCH /api/admin/doctors/:id/reinstate`, reason required).
  Care clears its local suspension with `identity_sync_status='pending'`, then calls
  `PATCH /internal/users/:id/status` `{ status: "active" }`.
- **Provider change (identity-service, ships first):** the internal status route accepts `suspended → active`
  (idempotent: already `active` → 200). The public admin route keeps refusing doctor targets.
- **Failure policy: retry, report pending** (same as Case 1): 3 inline attempts, then `202 identitySync: "pending"`
  and a durable retry; alert after 15 min; `409 InvalidStatusTransition` is non-retryable (page). The doctor stays
  unbookable until synced.
- Consultations flagged for follow-up at suspension stay flagged.

## Consequences
- ➕ No manual cross-database procedure; one audited path, still Care-only initiation.
- ➕ Fails safe: a pending reinstatement keeps the doctor blocked.
- ➖ Identity's internal contract widens one transition; identity ADR 0012 needs an amendment in identity-service.

## Alternatives considered
- **Must-not-degrade (Case 3 policy)** — rejected: restoring access is not security-critical.
- **Re-verification through Case 1** — rejected: forces re-credentialing after a mistaken suspension.
- **Keep ops-only** — rejected: drift risk.
