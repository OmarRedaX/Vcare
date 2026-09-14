---
title: "ADR 0003: Service-to-service auth with short-lived scoped service tokens"
owner: platform-team
service: platform
status: accepted
diataxis: explanation
date: 2026-09-14
last_verified: 2026-09-14
tags: [adr, decision, security, service-auth, jwt]
related: [landscape, adr-0001-two-service-split, glossary]
---

# ADR 0003 — Service tokens (client credentials) for service-to-service auth

- **Status:** Accepted
- **Date:** 2026-09-14
- **Deciders:** platform-team

## Context
Care calls Identity's internal endpoints to change account status (Cases 1 and 3) and to hydrate
profiles (Case 2); admin tooling calls Care's doctor summary; the Phase-2 AI service will call Care.
These endpoints change who may act on a medical platform, so the caller must be authenticated,
limited to what it needs, and unable to impersonate a user. PRD §4.5 names the anti-patterns: no
shared database, no static forever-key, never trust a caller-supplied `X-User-Id`.

## Decision
- Each calling service is a **service client** in Identity (`client_id`, argon2id-hashed secret,
  allowed scopes) and holds `SERVICE_CLIENT_ID` / `SERVICE_CLIENT_SECRET` from a secret store.
- It exchanges them at `POST /internal/auth/token` (`grant_type=client_credentials`, `scope`,
  `audience`) for a **300-second JWT**: EdDSA-signed, `iss=vcare-identity`, `typ=service`,
  `sub=<client_id>`, `aud=<requested audience>`, `scope`, `jti`. Requested scopes must be a subset of
  allowed scopes. No refresh token; the token endpoint is rate-limited to 60/min per client.
- Scopes: `users:read`, `users:status:write`, `doctors:read`.
- Callers cache the token until 30 s before expiry, single-flight refreshes, and retry once on `401`.
- **Internal routes are network-isolated**: `/internal/*` runs on a separate listener bound to the
  private network; the public ingress never routes it.
- Every internal route's `service-guard` requires a valid signature, `typ=service`, `aud` containing
  the provider, and the route's scope. **User tokens are rejected** (`401 ServiceTokenRequired`,
  even an admin's); missing scope → `403 InsufficientScope`.
- **Never trust `X-User-Id`, `X-Role`, `X-Forwarded-User`** or any caller-supplied identity header.
  The acting admin travels as `actorUserId` in the body and is recorded for audit, never used for
  authorization.

## Consequences
- ➕ A leaked service token is useful for at most 5 minutes and only for its scopes and audience.
- ➕ Least privilege per caller; the Phase-2 AI service gets its own client and scopes without
  touching existing ones.
- ➕ One verification path (EdDSA JWT via JWKS) for user and service tokens, distinguished by `typ`.
- ➕ Two layers: network isolation and token authentication; either alone is not trusted.
- ➖ Identity is on the path for obtaining tokens; mitigated by caching (a token lasts 300 s) and by
  Identity being a dependency-light Tier 1 service.
- ➖ Client secrets must be provisioned and rotated per environment.
- ➖ The token endpoint and service-guard are security-critical code that both services must test
  (user token rejected on every internal route, scope enforcement).

## Alternatives considered
- **Shared database** — Care reads/writes Identity tables directly. Rejected: destroys single-writer
  ownership, couples schemas, and lets Care change account status without Identity revoking sessions.
- **Static API keys** — simple, but long-lived, unscoped, hard to rotate, and a leak is permanent
  until noticed. Rejected.
- **mTLS only** — strong transport identity, but no per-route scopes, heavier certificate operations
  for a two-service MVP, and no uniform story for the Phase-2 service's permissions. Rejected as the
  sole mechanism; may be added later as defence in depth.
- **Forwarding user tokens** — Care calls Identity with the admin's access token. Rejected: blurs
  user and service authority, fails for background retry jobs where no user token exists (Case 3's
  durable retry), and widens what a user token can do.
