---
title: "ADR 0011: Browsers reach private object storage directly through presigned URLs"
owner: platform-team
service: platform
status: accepted
diataxis: explanation
date: 2026-09-15
last_verified: 2026-09-15
tags: [adr, decision, object-storage, edge, cors, security, uploads, downloads]
related: [deployment, data-ownership, glossary, adr-0005-single-origin-edge-routing, adr-0007-managed-container-platform]
---

# ADR 0011 — Browsers reach private object storage directly through presigned URLs

- **Status:** Accepted
- **Date:** 2026-09-15
- **Deciders:** platform-team (from care-service `/system-design` on file handling; care ADRs 0013–0015)

## Context
[ADR 0005](./0005-single-origin-edge-routing.md) serves the web app and both APIs from one origin with CORS
disabled. care-service now uploads verification documents and record attachments **directly** from the browser to a
private S3 bucket with presigned POSTs, and serves downloads as short-lived presigned GETs (care ADRs 0013, 0014).
S3 presigned signatures are bound to the bucket's host, so those requests cannot go through the single origin
without replacing them with CDN-signed URLs (which do not support presigned POST).

## Decision
- The **object-storage host is the one exception** to the single origin. Browsers talk to the private bucket's own
  HTTPS endpoint, only with presigned URLs issued by the owning service after authorization.
- **Bucket rules (every service that adopts this):** private, Block Public Access on, TLS-only bucket policy,
  server-side encryption; CORS `AllowedOrigins` = the web origin only, `AllowedMethods` = `POST` only, no
  credentials; downloads are plain navigations and need no CORS; presigned POST policies fix the key and size range;
  presigned GETs are short-lived and force `attachment` disposition.
- ADR 0005 is otherwise unchanged: APIs and the web app stay on the single origin with CORS disabled, and `/internal`
  and health are never routed.
- Each bucket belongs to exactly one service (hub ADR 0001) and is declared in [deployment.md](../architecture/deployment.md).

## Consequences
- ➕ File bytes never traverse API tasks or the edge; presigned POST enforces size before bytes land.
- ➕ The edge routing table does not change.
- ➖ A second public host in the browser's content-security policy (`connect-src`/`form-action` for the bucket).
- ➖ Bucket CORS is platform configuration that IaC must keep aligned with the web origin.

## Alternatives considered
- **Route `/files/*` on the single origin through the CDN** — keeps one origin, but needs CDN-signed URLs/cookies,
  loses presigned POST, and changes ADR 0005's routing table. Rejected.
- **A `files.` subdomain in front of the bucket** — still needs CORS and CDN signing, plus DNS and a certificate.
  Rejected.
