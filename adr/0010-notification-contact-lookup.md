---
title: "ADR 0010: care-service resolves notification recipients through an Identity contacts lookup"
owner: platform-team
service: platform
status: accepted
diataxis: explanation
date: 2026-09-15
last_verified: 2026-09-15
tags: [adr, decision, notifications, pii, data-ownership, cross-service]
related: [landscape, data-ownership, adr-0003-service-token-s2s-auth, adr-0001-two-service-split]
---

# ADR 0010 — care-service resolves notification recipients through an Identity contacts lookup

- **Status:** Accepted
- **Date:** 2026-09-15
- **Deciders:** platform-team, care-team (identity-team to confirm the provider change)

## Context
Care must email patients and doctors (PRD 7.11) through its transactional outbox (care ADR 0011), but Identity owns
email addresses and the data-ownership rule said email and phone never leave Identity through `/internal/*`. Care
must not store emails.

## Decision
- **Provider (identity-service, ships first):** `GET /internal/users/contacts?ids=` (≤ 100 ids) returning
  `{ id, email, fullName, locale, status }`; **no phone**. New scope **`users:contact:read`**, allowed only for the
  `care-service` client.
- **Consumer (care-service):** only `care-worker` requests the scope and calls the endpoint, once per outbox batch, at
  send time. The response is held in memory for that batch only — **never cached, stored, or logged**.
- **Failure policy: delay** — failures leave outbox rows pending with backoff; no user-facing request depends on it.
- The data-ownership rule becomes: *email leaves Identity only through the contacts lookup, to care-service's
  worker, for delivery; phone never leaves Identity.*

## Consequences
- ➕ Care owns its notification content and templates; Identity stays a leaf and the single writer of emails.
- ➕ PII exposure is narrow: one endpoint, one scope, one component, no persistence.
- ➖ A second PII-bearing internal endpoint to protect and audit (Identity logs scope use, not addresses).
- ➖ Email delivery depends on Identity availability (delay only).

## Alternatives considered
- **Identity sends emails for Care** (`POST /internal/notifications`) — rejected: Identity would own Care's templates
  and release cadence.
- **Copy emails into Care** — rejected: two writers of the same data (violates ADR 0001's ownership rule).
- **Add email to `GET /internal/users`** — rejected: that endpoint serves the hot Case-2 path and is cached in Redis.
