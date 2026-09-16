---
title: "ADR 0006: Doctor account status changes only through care-service"
owner: platform-team
service: platform
status: accepted
diataxis: explanation
date: 2026-09-15
last_verified: 2026-09-15
tags: [adr, decision, account-status, cross-service, integration]
related: [landscape, data-ownership, adr-0003-service-token-s2s-auth, glossary]
---

# ADR 0006 — Doctor account status changes only through care-service

- **Status:** Accepted — reinstatement clause amended by [ADR 0009](./0009-doctor-reinstatement-via-care.md)
- **Date:** 2026-09-15
- **Deciders:** platform-team, identity-team

## Context
The landscape recorded a known gap: an admin changing a doctor's status directly through Identity's
`PATCH /api/users/:id/status` was not propagated to Care (no events in the HTTP-only MVP). Care could keep a
suspended doctor bookable, or keep a reinstated doctor blocked. Mitigations relied on the admin console routing
doctor suspension through Care.

## Decision
- **Care is the only initiator of a doctor's account-status change.** It requests changes through
  `PATCH /internal/users/:id/status` (Cases 1 and 3); Identity remains the single writer of the status.
- Identity's public admin route refuses doctor targets with `403 Forbidden` (identity-service ADR 0012); it
  manages **patient** status only.
- Reinstating a suspended doctor has no API path in MVP (unchanged scope); an ops incident procedure updates
  both services together.

## Consequences
- ➕ The gap is closed by construction, without a message bus or callbacks; Identity stays a leaf.
- ➕ One path for doctor status → one place for audit, retries, and failure policy (Care).
- ➖ No emergency doctor suspension from Identity's API; admins use Care's console.
- ➖ Doctor reinstatement still requires a future Care-side flow (tracked in `TODO.md`).

## Alternatives considered
- **Identity notifies Care via outbox + a new Care internal endpoint** — rejected for MVP: cross-service contract
  and failure policy, and Identity would call Care.
- **`user.status_changed` event on a bus** — deferred with the bus decision.
- **Keep UI-level mitigations** — rejected: any direct API call reopens the gap.
