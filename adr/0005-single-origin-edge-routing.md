---
title: "ADR 0005: Single public origin with edge path routing"
owner: platform-team
service: platform
status: accepted
diataxis: explanation
date: 2026-09-15
last_verified: 2026-09-15
tags: [adr, decision, edge, routing, cookies, cors, security]
related: [landscape, adr-0001-two-service-split, adr-0007-managed-container-platform, glossary]
---

# ADR 0005 — Single public origin with edge path routing

- **Status:** Accepted
- **Date:** 2026-09-15
- **Deciders:** platform-team (from identity-service `/system-design`)

## Context
Both services expose `/api/*`. Identity's refresh cookie is `vcare_rt; HttpOnly; Secure; SameSite=Strict;
Path=/api/auth`, which only reaches Identity if the web app and API are same-site. Bearer-token calls from a
different origin trigger CORS preflights on every request. No domain topology had been chosen.

## Decision
The web app and both public APIs are served from **one origin** (placeholder `https://vcare.example`). An edge
(CDN + WAF) routes by path prefix:

| Path prefix | Target |
|---|---|
| `/api/auth/*`, `/api/users/*`, `/.well-known/*` | identity-service public listener |
| any other `/api/*` | care-service public listener |
| `/api/health/*`, `/internal/*` | **not routed** (`404` at the edge); health is probed by load balancers directly |
| everything else | static web app |

- Prefixes must not overlap. A service adding a new top-level public prefix changes the edge routing table in
  the same release (IaC), and updates this table.
- **CORS is disabled in production**; `CORS_ORIGINS` exists only for local development.
- WAF rate-based and bot rules protect `/api/auth/login`, `/api/auth/register/*`, `/api/auth/forgot-password`.
- The refresh cookie attributes are unchanged.

## Consequences
- ➕ No CORS configuration or preflight latency in production; the strict refresh cookie works as designed.
- ➕ One TLS certificate, one WAF, one place for edge rate limits.
- ➖ The edge routing table is shared configuration both teams must keep correct.
- ➖ Service boundaries are expressed as path prefixes, so a prefix cannot move between services without an edge change.

## Alternatives considered
- **`app.` + `api.` subdomains (same-site)** — independent web hosting; rejected: credentialed CORS and preflights on bearer calls.
- **Host per service (`identity.`, `care.`)** — rejected: two base URLs and CORS configs; boundaries leak into public URLs.
