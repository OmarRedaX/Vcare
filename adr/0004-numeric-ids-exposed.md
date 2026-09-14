---
title: "ADR 0004: Expose numeric BIGSERIAL ids on the wire"
owner: platform-team
service: platform
status: accepted
diataxis: explanation
date: 2026-09-14
last_verified: 2026-09-14
tags: [adr, decision, ids, api, security]
related: [data-ownership, landscape, glossary]
---

# ADR 0004 — Numeric ids are exposed

- **Status:** Accepted
- **Date:** 2026-09-14
- **Deciders:** product owner (during setup), platform-team

## Context
Both services use `BIGSERIAL` primary keys. The PRD's API surface uses those ids directly — for
example `GET /internal/users?ids=1,2,3` and `GET /internal/doctors/:userId/summary` — and Care
references Identity accounts only by user id. We had to choose whether the public and internal APIs
expose these database ids or a separate public identifier.

## Decision
The product owner decided during setup: **expose `BIGSERIAL` ids as numeric ids, as in the PRD**, on
both public and internal APIs. Cross-service references are numeric Identity user ids (`BIGINT`, no
foreign key). The following mitigations are mandatory:
- **Ids are never authorization.** Knowing an id grants nothing; every route runs deny-by-default
  RBAC plus an ownership predicate resolved from the database.
- **Private resources return `404 NotFound`** to non-owners (consultations, records, patient
  profiles), so ids cannot be used to probe for existence.
- **Rate limits** on public endpoints (e.g. search and slots 60/min per IP and 120/min per user;
  login 5/min per IP+email) bound enumeration attempts.
- Batch lookups omit unknown ids rather than erroring and never return email or phone.

## Consequences
- ➕ Simple: one id per row, no mapping layer, compact indexes, ids match the PRD and its examples.
- ➕ Cross-service references and batch calls (`ids=1,2,3`) stay small and cheap.
- ➖ Ids are **enumerable** and leak volume (e.g. roughly how many users or consultations exist).
- ➖ Consumers are **coupled to the provider's id space**: Care's `user_id` columns are Identity's
  sequence values, so re-keying or merging Identity data later would ripple into Care.
- ➖ Correctness of every ownership check matters more, because ids are guessable.

## Alternatives considered
- **Internal `BIGSERIAL` PK + public UUID column** — hides volume and decouples the wire from storage,
  at the cost of a second unique index per table, a mapping on every request, and diverging from the
  PRD's API. Rejected for MVP by the product owner.
- **UUIDv7 primary keys** — non-enumerable and time-ordered, but larger keys and indexes, a different
  cross-service reference type, and again diverges from the PRD. Rejected for MVP.
