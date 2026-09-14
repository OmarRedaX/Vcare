---
title: "ADR 0001: Split the platform into Identity and Care services"
owner: platform-team
service: platform
status: accepted
diataxis: explanation
date: 2026-09-14
last_verified: 2026-09-14
tags: [adr, decision, architecture, service-boundaries]
related: [prd, landscape, data-ownership, adr-0003-service-token-s2s-auth]
---

# ADR 0001 — Two services: Identity & Access, and Care

- **Status:** Accepted
- **Date:** 2026-09-14
- **Deciders:** platform-team, product owner

## Context
vcare is a network, not a clinic: thousands of independent doctors and millions of patients
([PRD §1](../product/prd.md)). The platform has two very different jobs — deciding *who someone is
and whether they may act*, and running *the medical marketplace* (doctors, schedules, consultations,
records). PRD §4.3 compares them:

| Dimension | Identity | Care |
|---|---|---|
| Traffic shape | login and token refresh — huge volume, tiny payloads, read-dominated | search, slot computation, booking — heavy queries and writes |
| Scaling trigger | total registered users | active consultations and search volume |
| Peak pattern | steady, spiky at campaigns | evening peaks, when people book |
| Data sensitivity | credentials | medical records — different retention, audit, and encryption rules |
| Consumers | every service, now and future | patients and doctors |

Phase 2 adds AI capabilities (PRD §12) that must authenticate users and services without touching
the marketplace database.

## Decision
Build **two independently deployable services, each with its own database**:
- **identity-service** (`vcare-identity-api`) — accounts, authentication, rotating refresh tokens,
  sessions, email verification, password management, account status, service clients.
- **care-service** (`vcare-care-api`) — doctor profiles and verification, specialties, schedules,
  consultations, video sessions, patient profiles, medical records, help content, audit.

Care never stores a password, never issues a token, and holds only numeric Identity user ids. Care
verifies user tokens locally (no call per request) and calls Identity only on the three integration
cases in [landscape.md](../architecture/landscape.md). The Phase-2 **AI & Retrieval** service will be
a **third** service that authenticates against Identity and calls Care's internal APIs — it adds a
service rather than moving this boundary.

## Consequences
- ➕ Each service scales on its own trigger: Identity on user count and login/refresh volume, Care on
  search and booking load.
- ➕ Credentials and clinical data live in separate databases with separate retention, audit, and
  encryption rules; a breach or bug in one does not expose the other.
- ➕ Identity is a stable shared foundation for every current and future consumer, including Phase 2.
- ➕ The boundary is visible in the PRD's own integration cases, so it is unlikely to move.
- ➖ Cross-service consistency is explicit work: Cases 1 and 3 need local-first state, retries,
  durable jobs, and alerts; Case 2 needs batching, caching, and a degrade path.
- ➖ Two deployables, two databases, service-to-service auth, and request-id propagation to operate.
- ➖ Without events, a status change made directly in Identity is not seen by Care (known gap, tracked
  in [TODO.md](../TODO.md)).

## Alternatives considered
- **Modular monolith (one deployable, one database, identity and care modules)** — cheaper to start
  and simple transactions across the boundary. Rejected: login/refresh and search/booking have
  opposite traffic shapes and scaling triggers, credentials and clinical records would share one
  database and one blast radius, and the Phase-2 AI service would need to authenticate against a
  monolith that also holds medical records.
- **Finer-grained microservices (separate auth, users, doctors, scheduling, consultations, records,
  help services)** — rejected: scheduling, consultations, and records share transactions (booking
  with an exclusion constraint, record-after-completion, suspension flagging consultations); splitting
  them turns local transactions into distributed ones with no business driver, and multiplies the
  operational cost before any single domain has earned independence.
