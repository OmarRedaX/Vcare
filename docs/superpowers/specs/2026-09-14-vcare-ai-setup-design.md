---
title: vcare — AI/Claude setup across three repos (design)
owner: platform-team
service: platform
status: approved
diataxis: explanation
last_verified: 2026-09-14
tags: [design, ai-setup, hub-and-spoke, workflow, skills]
related: [prd, landscape, data-ownership, adr-0002-hub-and-spoke-docs]
---

# vcare — AI/Claude setup (3 repos) — Design

_Date: 2026-09-14 • Status: Approved • Source of intent: [product/prd.md](../../../product/prd.md)_

## 1. Goal
Initialize the **AI/Claude setup only** — no application code — for the Virtual Care Platform, as
**three independent git repos** (not a monorepo), replicating the hub-and-spoke pattern of
`reference-repos/{playground-with-context, playground-notifications, playground-hub}` and making it
stricter. Backend only.

## 2. Layout
```
E:\Full Stack Projects\Vcare\VCare\       ← nothing placed at this root
  vcare-identity-api/   SPOKE — Identity & Access (accounts, auth, tokens, sessions, status)
  vcare-care-api/       SPOKE — Care (doctors, verification, schedules, consultations, records, help, audit)
  vcare-hub/            HUB   — cross-service docs; no .claude/ by design
```
Each is its own `git init` repo. Spokes find the hub at `../vcare-hub`; the hub finds spokes at
`../vcare-identity-api` and `../vcare-care-api`.

### Per-spoke tree
```
CLAUDE.md
skills-lock.json
.gitignore                      # Node
.gitattributes                  # * text=auto eol=lf (keeps .sh runnable under Git Bash)
.claude/
  settings.json                 # committed team permissions (allow + deny)
  settings.local.json           # committed, as in the reference and the prompt's deliverable list
  agents/flow-{spec-author,developer,test-author,qa-runner,code-reviewer,docs-updater}.md
  commands/{brainstorm,construct-spec,develop,write-tests,manual-qa,review-code,update-docs,develop-feature-e2e,system-design}.md
  skills/<name>/SKILL.md        # installed (skills.sh) + hand-authored, all here
contracts/openapi.yaml          # OpenAPI 3.1 — SOURCE OF TRUTH (incl. /internal/*)
docs/
  INDEX.md  service-card.md  system-design.md  runbook.md  quickstart.md
  architecture/*.md
  adr/NNNN-*.md
```
No `src/`, no per-module `docs/<module>/` folders — the workflow creates those when a module is built.

## 3. Decisions taken in brainstorming
| # | Decision | Chosen | Consequence |
|---|---|---|---|
| D1 | Repo location | `E:\Full Stack Projects\Vcare\VCare\` | relative hub path `../vcare-hub` |
| D2 | User token transport | `Authorization: Bearer` access token + rotating refresh token in httpOnly `Secure` `SameSite=Strict` cookie scoped to `/auth/refresh` | one auth path for users, service tokens, and the Phase-2 AI service |
| D3 | Request DTO validation | `class-validator` + `class-transformer` (reference); `zod` for env only | Care parses Identity responses with class-validator DTOs too |
| D4 | Exposed identifiers | numeric `BIGSERIAL` ids, as the PRD shows (`/internal/users?ids=1,2,3`) | enumeration mitigated by deny-by-default ownership checks + rate limits; recorded as hub ADR 0004 |

## 4. Spoke `CLAUDE.md` — shared production baseline (stricter than reference)
Sections are **named, not numbered**, and every agent/command cites them by name
(e.g. "CLAUDE.md → Security rules").

**Locked stack:** Node 24 LTS · TypeScript strict · Express 5 · class-validator/class-transformer ·
tsyringe · zod (env) · Knex over `pg`, raw-SQL migrations (ORMs forbidden) · ioredis · `jose`
(EdDSA JWT, JWKS) · Jest + supertest · helmet · structured JSON logger.
Identity adds `argon2` (bcrypt fallback). Care adds `luxon` (IANA tz) and `undici` (internal client).

**Shared strict rules**
- **Error envelope** (both services, identical): `{ "success": false, "error": { "code", "message", "details?", "requestId" } }`; success `{ "success": true, "data", "meta?" }`.
- **Request id**: `X-Request-Id` accepted or generated, returned on every response, forwarded on every internal call, present on every log line.
- **RBAC + ownership on every endpoint**: deny-by-default; each route declares `roles` and an ownership rule; a route without one is a review blocker.
- **Contract-first**: edit `contracts/openapi.yaml` before code; code/spec vs contract → contract wins.
- **Time**: `TIMESTAMPTZ`, UTC in storage, ISO-8601 with offset on the wire; users see their own tz.
- **Soft delete** only (`deleted_at`); hard delete never exposed.
- **Money**: INT minor units + `currency CHAR(3)`.
- **Pagination**: cursor-based on every list; filterable.
- **Service-to-service auth**: Identity `POST /internal/auth/token` (client-credentials) → ~5-min JWT with `typ=service`, `aud`, `scope` (`users:read`, `users:status:write`, `doctors:read`). `/internal/*` is network-isolated, accepts only service tokens, rejects user tokens. Never trust `X-User-Id` or any caller-supplied identity header.
- **Logs**: no PII, credentials, tokens, or clinical data.

**Identity deltas**: argon2id (bcrypt fallback for legacy hashes, rehash on login); 15-min access token;
rotating refresh with reuse detection (reuse → revoke family); status → `suspended`/`rejected`
revokes all refresh tokens in the same transaction; `/internal/users?ids=` (batch, max 100) and
`PATCH /internal/users/:id/status`; `GET /.well-known/jwks.json` for local verification.

**Care deltas**: `btree_gist` `EXCLUDE USING gist (doctor_id WITH =, tstzrange(starts_at, ends_at, '[)') WITH &&) WHERE (status NOT IN ('cancelled','no_show'))`;
slots never stored (computed in doctor tz, rendered in patient tz); booking/reschedule/cancel idempotent
on `Idempotency-Key`; internal calls 2s timeout + retry/backoff — Case 2 degrades to Redis-cached
profiles, Case 3 must not degrade (retry until success + alert); every clinical-record access audited;
records append-only after 24h (amendments); signed expiring URLs for documents/attachments;
Phase-2 AI is draft-the-doctor-confirms, red flags escalate to a human.

**Wiring**: each `CLAUDE.md` maps the phrase "let's system design" → `/system-design`.

## 5. Workflow (agents + commands)
- 6 `flow-*` subagents and 8 commands replicate the reference, reworded per service, strict rules folded in.
- **`/system-design <topic>`** — inline, interactive, Socratic (one question at a time; 2–3 options + recommendation; user decides). Reads hub first (`../vcare-hub/INDEX.md` → landscape, data-ownership, contracts), then writes `docs/system-design.md`, `docs/architecture/*.md`, `docs/adr/NNNN-*.md`; for cross-service topics also updates hub `architecture/landscape.md` + `data-ownership.md`. No subagent for dialogue or writing.
- **Parallelism** (fan-out at the command level; subagents cannot spawn subagents):
  - `/review-code` — gate: module ≥3 files or ≥150 changed lines. Five parallel dimension reviewers (correctness · security/RBAC+clinical · domain rules · perf/indexing · contract-drift) → adversarial verification of each finding → one review file. Below the gate: single `flow-code-reviewer`.
  - `/construct-spec`, `/system-design` — parallel read-only recon when ≥2 large sources.
  - `/develop-feature-e2e` — ≥2 independent units → concurrent builds in isolated git worktrees; cross-service topics build the provider contract before the consumer; serial on real dependencies.

## 6. Skills
**Installed** from `mindrally/skills` (copied real `SKILL.md` into `.claude/skills/<name>/`; `.agents/` not used):
both spokes (18) — postgresql-best-practices, sql-best-practices, redis-best-practices, express-typescript,
nodejs-development, typescript, zod-schema-validation, clean-architecture, microservices,
performance-optimization, jest, testing, security-best-practices, jwt-security, docker,
ci-cd-best-practices, observability-guidelines, git-workflow. Identity + oauth-implementation.
Care + rabbitmq-development. Excluded: ORMs, nestjs/graphql/grpc/trpc/fastapi, cypress/playwright, auth0/clerk.
`skills-lock.json` records source, registry commit sha, path, and `computedHash` = sha256 of the
copied `SKILL.md` bytes (`hashMethod: sha256-file`), since the reference lock's hash is not a plain file sha256.

**Hand-authored**: `write-migration` (raw SQL, `TIMESTAMPTZ`, soft delete, `btree_gist` exclusion),
`cross-service-integration` (3 cases, degrade vs must-not-degrade, service-token flow),
`rbac-ownership-guard` (deny-by-default, permissions matrix, clinical-access audit);
Care only `timezone-slot-computation` (algorithm, doctor-tz→patient-tz, booking rules, hot-path budget).

## 7. Docs & contracts
Mandatory frontmatter on every doc: `title, owner, service, status, last_verified, tags, related`
(+ `module`, `diataxis` where they apply). Diátaxis is a label, not a folder tree. Seeded docs are
`status: draft` (derived from the PRD); `/system-design` refines them.

- **Identity architecture shards**: overview, data-model, api, auth-tokens, service-auth, infrastructure, future.
- **Care architecture shards**: overview, data-model, api, scheduling-slots, consultation-lifecycle, clinical-records, rbac, integration, resilience, infrastructure, future.
- **ADRs** — Identity: 0001 no-ORM Knex raw SQL · 0002 asymmetric JWT + rotating refresh · 0003 argon2id.
  Care: 0001 no-ORM · 0002 slots never stored · 0003 DB exclusion constraint · 0004 cross-service failure policies.
- **Contracts**: OpenAPI 3.1 per spoke covering PRD §14 plus `/internal/*`, `/health`, JWKS; shared error envelope; bearer + service-token security schemes. No AsyncAPI — events listed as future.

## 8. Hub (`vcare-hub`)
`CLAUDE.md` (hub-and-spoke + 6-step retrieval escalation) · `INDEX.md` router (links PRD as source of
intent) · `catalog/` (service-catalog + synced `identity-service.card.md`, `care-service.card.md`) ·
`contracts/` (synced `<service>.openapi.yaml`) · `architecture/landscape.md` (C4 L1/L2 + the 3
integration cases) · `architecture/data-ownership.md` · `adr/` (0001 two-service split · 0002
hub-and-spoke docs · 0003 service-token S2S auth · 0004 numeric ids exposed) · `glossary.md` ·
`product/prd.md` · `scripts/{sync-from-spoke,check-freshness}.sh` · `README.md` · `TODO.md`. No `.claude/`.

## 9. Build & verification
1. Author inline: both `CLAUDE.md`, agents, commands, project skills.
2. Parallel subagents: Identity docs+contract · Care docs+contract · hub content (+ PRD copy).
3. Script-install registry skills; compute lock hashes.
4. Run `sync-from-spoke.sh` for both spokes; run `check-freshness.sh`; lint both OpenAPI files (`@redocly/cli lint`).
5. `git init` + commit each repo.

**Success criteria**: no application code anywhere; every doc has valid frontmatter; freshness check
passes; both contracts lint without errors; every skill resolves at `.claude/skills/<name>/SKILL.md`
with a matching lock hash; agent/command files contain no `CLAUDE.md §<number>` citations; hub cards
and contracts byte-match the spokes (plus sync header).
