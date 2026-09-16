---
title: "ADR 0007: Services run on a managed container platform"
owner: platform-team
service: platform
status: accepted
diataxis: explanation
date: 2026-09-15
last_verified: 2026-09-15
tags: [adr, decision, deployment, infrastructure, devops, containers]
related: [landscape, adr-0001-two-service-split, adr-0005-single-origin-edge-routing]
---

# ADR 0007 — Services run on a managed container platform

- **Status:** Accepted
- **Date:** 2026-09-15
- **Deciders:** platform-team (from identity-service `/system-design`)

## Context
Two Tier-1 Node.js services, each one image with a public and a private listener, own databases, Redis, and a
small team. Identity targets 99.95 % monthly availability with multi-AZ Postgres; `/internal/*` must be
reachable only on the private network. No hosting platform had been chosen.

## Decision
- Every vcare service deploys as **containers on a managed container service** — reference target **AWS ECS on
  Fargate**; switching provider or moving to Kubernetes requires a superseding ADR.
- **Per service:** one immutable image (tag = commit SHA); an API service with ≥ 2 tasks across ≥ 2 AZs; background
  work either as a separate service (identity-service worker) or inside API tasks (care-service retrier) at the
  service's choice; migrations as a **one-off task before rollout** (expand → migrate → contract).
- **Networking:** public load balancer behind the edge (hub ADR 0005) exposes only the public port; the internal
  port is reachable only via a private load balancer or service discovery, with security groups admitting
  registered callers only.
- **Data:** each service has its **own** managed PostgreSQL (Multi-AZ) and managed Redis — never shared (hub ADR 0001).
- **Secrets** from a managed secrets store; **all infrastructure as code**; logs to the platform log service.

## Consequences
- ➕ No cluster to operate; multi-AZ, private networking, and managed failover out of the box.
- ➕ Same unit (a container image) keeps a later move to Kubernetes feasible.
- ➖ Coupling to one cloud's service model (load balancers, service discovery, log formats).
- ➖ Fewer built-in deployment strategies (canaries) than a Kubernetes ecosystem.

## Alternatives considered
- **Kubernetes (EKS/GKE/AKS)** — portable, rich ecosystem; rejected for now: cluster operations outweigh the benefit
  for two services; revisit when Phase 2 and more services arrive.
- **PaaS / VMs** — cheapest start; rejected: private `/internal` networking, multi-AZ, and managed synchronous
  standby are weak or manual for Tier 1.
