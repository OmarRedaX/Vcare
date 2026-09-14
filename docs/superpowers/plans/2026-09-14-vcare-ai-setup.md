---
title: vcare — AI/Claude setup implementation plan
owner: platform-team
service: platform
status: approved
diataxis: how-to
last_verified: 2026-09-14
tags: [plan, ai-setup, workflow]
related: [vcare-ai-setup-design, prd]
---

# vcare AI/Claude Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce three independent git repos (`vcare-identity-api`, `vcare-care-api`, `vcare-hub`) containing the complete AI/Claude setup — CLAUDE.md, agents, commands, skills, settings, docs, contracts, hub — and zero application code.

**Architecture:** Hub-and-spoke. Spokes own the dev workflow (`.claude/`) and their docs/contracts; the hub aggregates service cards + contracts via `sync-from-spoke.sh` and owns org-level architecture, ADRs, glossary, and the PRD. Crown-jewel files are authored inline; docs+contracts for each spoke and the hub are produced by three parallel subagents.

**Tech Stack (documented, not installed):** Node 24 LTS, TypeScript strict, Express 5, class-validator/class-transformer, tsyringe, zod (env), Knex + pg (raw SQL), ioredis, jose (EdDSA), Jest + supertest, argon2 (Identity), luxon + undici (Care). Tooling used now: git, bash (Git Bash), curl, python, `npx @redocly/cli`.

**Spec:** `vcare-hub/docs/superpowers/specs/2026-09-14-vcare-ai-setup-design.md` (read it first).

## Global Constraints

- Root: `E:\Full Stack Projects\Vcare\VCare\` (bash: `/e/Full Stack Projects/Vcare/VCare`). Nothing is written at this root.
- References (read-only): `E:\Full Stack Projects\Vcare\reference-repos\{playground-with-context,playground-notifications,playground-hub}`. PRD source: `E:\Full Stack Projects\Vcare\INITIALIZE-VCARE-PROMPT.md` lines 87–320.
- No application code: no `src/`, `tests/`, `package.json`, `tsconfig.json`, migrations, or `.ts` files in any repo.
- Every `.md` under `docs/`, hub `catalog/`, `architecture/`, `adr/`, `product/`, `glossary.md`, `INDEX.md` carries frontmatter `title, owner, service, status, last_verified: 2026-09-14, tags, related` (+ `module`/`diataxis` where they apply). Exempt: `CLAUDE.md`, `README.md`, `TODO.md`, `.claude/**`.
- Owners: `identity-team` (Identity), `care-team` (Care), `platform-team` (hub). Service ids: `identity-service`, `care-service`.
- Agents/commands cite CLAUDE.md **by section name**; the regex `CLAUDE\.md ?§ ?[0-9]` must match nothing.
- IDs exposed are numeric (`BIGSERIAL`); user tokens are `Authorization: Bearer` (EdDSA JWT, 15 min) + rotating refresh in httpOnly `Secure` `SameSite=Strict` cookie at path `/api/auth` (covers refresh + logout); DTO validation is class-validator.
- Error envelope, both services: `{"success":false,"error":{"code":"<PascalCase>","message":"...","details":[...]?,"requestId":"<uuid>"}}`; success `{"success":true,"data":...,"meta":{...}?}`. Header `X-Request-Id`.
- Service token: `POST /internal/auth/token` (client_credentials) → JWT `typ=service`, `aud=<target-service>`, `scope` ∈ `users:read users:status:write doctors:read`, TTL 300 s.
- Line endings LF (`.gitattributes`). Commits end with the two attribution lines from the session.

### Canonical CLAUDE.md section names (identical headings in both spokes)
Agents and commands cite exactly these strings:
1. `Mission of this service`
2. `Tech stack (locked)`
3. `Folder structure and layering`
4. `Naming conventions`
5. `Module file conventions`
6. `Database rules`
7. `API conventions`
8. `Authentication and service-to-service auth`
9. `Authorization — RBAC and ownership`
10. `Security rules`
11. `Privacy and logging`
12. `Cross-service integration`
13. `Domain rules`
14. `Testing policy`
15. `Performance rules`
16. `Code style — what to avoid`
17. `Build order for a new module`
18. `Out of scope`
19. `Workflow and documentation discipline`
20. `Architect mode — /system-design`
21. `Documentation structure`
22. `Cross-service context (the hub)`

---

## Phase 1 — Author inline (crown jewels)

### Task 1: Scaffold both spoke repos

**Files:**
- Create: `vcare-identity-api/.gitignore`, `vcare-identity-api/.gitattributes`
- Create: `vcare-care-api/.gitignore`, `vcare-care-api/.gitattributes`

**Interfaces:**
- Produces: two initialized git repos on branch `main` with empty `.claude/{agents,commands,skills}`, `contracts/`, `docs/{architecture,adr}` directories.

- [ ] **Step 1: Init repos and dirs**
```bash
cd "/e/Full Stack Projects/Vcare/VCare"
for r in vcare-identity-api vcare-care-api; do
  git -C "$r" init -q -b main
  mkdir -p "$r/.claude/agents" "$r/.claude/commands" "$r/.claude/skills" "$r/contracts" "$r/docs/architecture" "$r/docs/adr"
  printf '* text=auto eol=lf\n*.sh text eol=lf\n' > "$r/.gitattributes"
done
```
- [ ] **Step 2: Write the Node `.gitignore`** (same in both): the reference `playground-with-context/.gitignore` minus `package-lock.json`/`yarn.lock` lines (lockfiles are committed), plus `.env.*` except `!.env.example`, `.agents/` (skills.sh cross-agent dir is not used).
- [ ] **Step 3: Verify**
Run: `for r in vcare-identity-api vcare-care-api; do git -C "$r" rev-parse --abbrev-ref HEAD; done`
Expected: `main` twice.

### Task 2: Identity `CLAUDE.md`

**Files:** Create `vcare-identity-api/CLAUDE.md`

**Interfaces:**
- Consumes: canonical section names (Global Constraints).
- Produces: section names cited by Tasks 4–6; error codes `InvalidCredentials, EmailNotVerified, AccountSuspended, AccountPending, AccountRejected, RefreshTokenReused, RefreshTokenInvalid, TokenExpired, Forbidden, Unauthorized, ValidationFailed, NotFound, Conflict, RateLimited, ServiceTokenRequired, InsufficientScope, InternalError`.

- [ ] **Step 1: Write all 22 sections** with these service-specific contents:
  - *Mission*: accounts, authentication, roles (patient/doctor/admin), sessions, email verification, password management, account status (pending/active/suspended/rejected). Never stores clinical/professional data.
  - *Tech stack (locked)*: table from Tech Stack + `argon2`; forbidden list (ORMs, nestjs, graphql, grpc, trpc, auth0/clerk, passport).
  - *Folder structure and layering*: reference `app/ lib/ pkg/` layering, plus `lib/auth/{jwt,jwks,guard,service-guard}`, `lib/rbac/`, `lib/request-id/`, `src/app/internal/` for `/internal/*`.
  - *Database rules*: raw-SQL migrations, `TIMESTAMPTZ`, `deleted_at` soft delete, named constraints, `citext` email unique among non-deleted rows (partial unique index), refresh tokens stored as sha256 hash only.
  - *API conventions*: envelope, `X-Request-Id`, cursor pagination (`cursor, limit≤100`), `Idempotency-Key` on POST `/auth/register`, internal routes under `/internal`, public under `/api`.
  - *Authentication and service-to-service auth*: EdDSA keypair, `kid` rotation, JWKS at `/.well-known/jwks.json`; access 15 min claims `sub, role, status, email_verified, typ=user`; refresh 30 days, rotate on every use, family id, reuse → revoke family + `RefreshTokenReused`; client-credentials endpoint and scopes; internal guard rejects `typ!=service`; never read `X-User-Id`.
  - *Authorization — RBAC and ownership*: deny-by-default `authorize({roles, owner})` on every route; matrix for Identity routes from PRD §14 (admin: `/users*`, `PATCH /users/:id/status`, sessions; self: `/auth/me`).
  - *Security rules*: argon2id (m=19456 KiB, t=2, p=1), bcrypt fallback verify+rehash, rate limits on login/register/forgot/reset/refresh, generic login errors, reset/verification tokens single-use hashed with 30 min / 24 h expiry, helmet, CORS allowlist.
  - *Privacy and logging*: never log passwords, hashes, tokens, email, phone; log `userId` + `requestId`.
  - *Cross-service integration*: Identity is the provider — `/internal/users?ids=` (≤100, missing ids omitted, returns `id, fullName, avatarUrl, role, status, timezone, locale`), `PATCH /internal/users/:id/status` (idempotent; suspended/rejected revoke all refresh tokens in the same transaction; returns new status); cite `cross-service-integration` skill.
  - *Domain rules*: status transitions `pending→active|rejected`, `active→suspended`, `suspended→active`, `rejected→pending` (re-open); patients start `active` after email verification; doctors start `pending`; admins are seeded; login blocked for suspended/rejected; password change revokes other sessions.
  - *Testing policy*: reference policy verbatim in spirit + token rotation/reuse and suspension-revokes tests mandatory.
  - *Performance rules*: login p95 < 150 ms excluding argon2 cost budget, `/internal/users` p95 < 50 ms for 100 ids, single `WHERE id = ANY($1)` query.
  - *Out of scope*: OAuth social login, MFA, SMS, payments; events future.
  - *Workflow and documentation discipline*, *Documentation structure*, *Cross-service context (the hub)*: reference sections adapted; hub at `../vcare-hub`; retrieval escalation 6 steps.
  - *Architect mode — /system-design*: phrase "let's system design" or `/system-design <topic>` → run the command inline.
- [ ] **Step 2: Verify headings**
Run: `grep -c '^## ' vcare-identity-api/CLAUDE.md` → Expected `22`; `grep -nE '§ ?[0-9]' vcare-identity-api/CLAUDE.md` → Expected no output.

### Task 3: Care `CLAUDE.md`

**Files:** Create `vcare-care-api/CLAUDE.md`

**Interfaces:**
- Consumes: canonical section names; Identity internal API shapes from Task 2.
- Produces: Care error codes `SlotUnavailable, OutsideWorkingHours, BookingInPast, BeyondBookingHorizon, DoctorNotBookable, EmailNotVerified, PolicyWindowViolation, InvalidTransition, NoShowTooEarly, RoomNotOpen, RecordLocked, RecordRequiresCompleted, NotAssignedDoctor, IdempotencyConflict, IdentityUnavailable, Forbidden, Unauthorized, ValidationFailed, NotFound, Conflict, RateLimited, InternalError`.

- [ ] **Step 1: Write all 22 sections** with these service-specific contents:
  - *Mission*: doctor profiles, verification documents, specialties, working hours, exceptions, consultation types, consultations, sessions, patient profiles, medical records + attachments, help articles, audit log. Never stores passwords or issues tokens; holds `user_id BIGINT` references (no FK across services).
  - *Tech stack (locked)*: + `luxon`, `undici`; forbidden list as Identity.
  - *Database rules*: `CREATE EXTENSION btree_gist`; exclusion constraint text from spec §4; `TIMESTAMPTZ`; `deleted_at`; WorkingHours `start_time/end_time TIME` interpreted in the doctor's tz; records `locked_at = created_at + 24h`; amendments table append-only.
  - *API conventions*: as Identity; `Idempotency-Key` **required** on `POST /consultations`, `PATCH /consultations/:id/reschedule`, `PATCH /consultations/:id/cancel`, same key + different body → `IdempotencyConflict` 422.
  - *Authentication and service-to-service auth*: verify user JWTs locally via cached JWKS (refresh on unknown `kid`); `status` claim must be `active` for doctors acting as doctors; obtain service token via client credentials, cache until 30 s before expiry.
  - *Authorization — RBAC and ownership*: PRD §9 matrix + §8 rules 17–19; admins never read clinical fields (records endpoints deny admin).
  - *Security rules*: signed URLs (HMAC, ≤10 min TTL) for documents/attachments; upload MIME allowlist; rate-limit public search.
  - *Privacy and logging*: no complaint text, notes, diagnosis, allergies, documents, names, emails in logs; every clinical read/write → `audit_logs` row (actor, action, entity, id, requestId).
  - *Cross-service integration*: Case 1 (approve/reject → `PATCH /internal/users/:id/status`; Care decision persisted first; on Identity failure the application stays `approved_pending_sync` and is retried), Case 2 (batch hydrate ≤100 ids, Redis TTL 300 s, degrade to cached or `displayName: null`), Case 3 (suspend → block bookings + flag consultations in one transaction, then status call with retry/backoff until success, alert after 3 failures; suspension never reported complete until Identity confirms); 2 s timeout, 3 retries exponential backoff with jitter for Case 1/2; cite `cross-service-integration` skill.
  - *Domain rules*: PRD §8 rules 1–22 verbatim-numbered as a list, lifecycle `booked → waiting → in_progress → completed` + `cancelled`, `no_show`; policy window 2 h; grace period 10 min; horizon 60 days; waiting room opens 10 min before start; Phase-2 AI boundary (draft-the-doctor-confirms, red flags escalate, never diagnoses/prescribes).
  - *Performance rules*: search < 400 ms, 14-day slot computation < 300 ms; cite `timezone-slot-computation` skill.
  - *Out of scope*: PRD §13 list; events/RabbitMQ future (email notifications async via outbox table only when that module is designed).
  - Remaining sections as Identity, adapted.
- [ ] **Step 2: Verify headings** — `grep -c '^## ' vcare-care-api/CLAUDE.md` → `22`; `diff <(grep '^## ' vcare-identity-api/CLAUDE.md) <(grep '^## ' vcare-care-api/CLAUDE.md)` → no output.

### Task 4: Agents (6 × 2)

**Files:** Create `vcare-{identity,care}-api/.claude/agents/flow-{spec-author,developer,test-author,qa-runner,code-reviewer,docs-updater}.md`

**Interfaces:**
- Consumes: canonical section names; reference agents.
- Produces: `subagent_type` names used by Task 5 commands.

- [ ] **Step 1:** Port each reference agent (frontmatter `name, description, tools, model: inherit`), folding the "Advanced doc structure" appendix into the body, replacing `§N` with section names, "modular monolith" with "this service (<service-id>)", httpOnly-cookie auth with Bearer + refresh cookie, OpenAPI-only contracts (no AsyncAPI).
- [ ] **Step 2: Strict additions** — spec-author: every endpoint lists roles + ownership rule + error codes from the envelope; developer: contract edit before code, RBAC declared per route, no PII logs; test-author: RBAC matrix test per route, exclusion-constraint concurrency test (Care), refresh reuse test (Identity); qa-runner: Bearer header + `Idempotency-Key`, `X-Request-Id` echoed; code-reviewer: accepts a `dimension` input (`correctness|security-rbac-clinical|domain-rules|perf-indexing|contract-drift|all`) and a `verify-findings` mode that tries to refute each candidate finding; docs-updater: service card + INDEX + contract drift.
- [ ] **Step 3: Verify** — `grep -rnE '§ ?[0-9]' vcare-*/.claude/agents` → no output; `ls vcare-*/.claude/agents | grep -c flow-` → `12`.

### Task 5: Commands (9 × 2)

**Files:** Create `vcare-{identity,care}-api/.claude/commands/{brainstorm,construct-spec,develop,write-tests,manual-qa,review-code,update-docs,develop-feature-e2e,system-design}.md`

**Interfaces:**
- Consumes: agent names from Task 4; section names.

- [ ] **Step 1:** Port the 8 reference commands (frontmatter `description, argument-hint, allowed-tools, disable-model-invocation: true, model: inherit`), appendix folded in, section names only.
- [ ] **Step 2: Parallelism** —
  - `review-code.md`: compute size (`git diff --stat` + file count under the module); if ≥3 files or ≥150 changed lines dispatch five `flow-code-reviewer` subagents **in one message** (one per dimension, candidates only, no file writes), then one `flow-code-reviewer` in `verify-findings` mode with all candidates, which writes the single review file; else one reviewer with `dimension: all`.
  - `construct-spec.md`: if ≥2 large sources (>300 lines each among brainstorm, contract section, hub docs, sibling spec) dispatch parallel `Explore` readers returning digests, then `flow-spec-author` with digests.
  - `develop-feature-e2e.md`: build a dependency graph of units; ≥2 independent units → parallel `flow-developer` subagents with `isolation: worktree`; cross-service → provider contract + implementation first, consumer after; merge worktrees serially; review/fix loop per unit.
- [ ] **Step 3: `/system-design`** — `system-design.md` with `allowed-tools: Read, Write, Edit, Grep, Glob, Bash, AskUserQuestion, Agent`, body: read `../vcare-hub/INDEX.md`, `architecture/landscape.md`, `data-ownership.md`, `product/prd.md` section for the topic, own `docs/system-design.md` + shards + ADRs + contract; optional parallel `Explore` recon when ≥2 large sources; Socratic loop (one question per message, 2–3 options with trade-offs + recommendation, user decides); present design in sections; then write `docs/system-design.md` router rows, `docs/architecture/<topic>.md`, next `docs/adr/NNNN-<slug>.md`, and for cross-service topics edit `../vcare-hub/architecture/landscape.md` + `data-ownership.md` (+ `adr/` if platform-wide) with frontmatter bumps; flag contract changes; never write application code.
- [ ] **Step 4: Verify** — `ls vcare-*/.claude/commands | grep -c '\.md$'` → `18`; `grep -rnE '§ ?[0-9]' vcare-*/.claude/commands` → no output.

### Task 6: Project skills + settings

**Files:**
- Create: `vcare-{identity,care}-api/.claude/skills/{write-migration,cross-service-integration,rbac-ownership-guard}/SKILL.md`
- Create: `vcare-care-api/.claude/skills/timezone-slot-computation/SKILL.md`
- Create: `vcare-{identity,care}-api/.claude/settings.json`, `.claude/settings.local.json`

- [ ] **Step 1: `write-migration`** — reference skill with: `TIMESTAMPTZ` everywhere (datatype table updated), `deleted_at TIMESTAMPTZ` + partial unique indexes `WHERE deleted_at IS NULL`, no `ON DELETE CASCADE` on clinical tables, `btree_gist` exclusion constraint section with the exact Care SQL and a note that the service maps `23P01 exclusion_violation` → `SlotUnavailable` 409, numeric-id exposure note (no `public_id` column).
- [ ] **Step 2: `cross-service-integration`** — service-token flow (sequence), the three cases with ordering + failure policy table (Case 1 retry+pending-sync, Case 2 degrade, Case 3 must-not-degrade), client rules (2 s timeout, backoff `200ms·2^n ± jitter`, forward `X-Request-Id`, batch ≤100), provider rules (scopes, reject user tokens, idempotent status PATCH), checklist.
- [ ] **Step 3: `rbac-ownership-guard`** — deny-by-default `authorize({roles, owner})` contract, PRD §9 matrix + §8 access rules as a table of route → roles → ownership predicate for both services, clinical-access audit requirement, tests required per route (role denied, non-owner denied, owner allowed).
- [ ] **Step 4: `timezone-slot-computation`** (Care) — algorithm: for each date in the doctor tz within `[from, to]` clipped to now..now+60 d → WorkingHours intervals (split shifts) → apply exceptions (day_off removes, custom_hours replaces) → subtract booked non-terminal consultations → slice by type duration aligned to interval start → drop starts < now → convert to UTC → render in patient tz; DST rules (skip nonexistent local times, dedupe ambiguous), booking re-validation inside the transaction + exclusion constraint as the final guard; hot-path budget (one query per input set, Redis cache of the availability window keyed by doctor+type+range invalidated on booking/exception change, 14 days < 300 ms).
- [ ] **Step 5: Settings** — `settings.json`: allow `Bash(git status*)`, `Bash(git diff*)`, `Bash(git log*)`, `Bash(npm run *)`, `Bash(npx tsc *)`, `Bash(npx jest *)`, `Bash(npx @redocly/cli lint *)`, `Bash(curl -s http://localhost*)`; deny `Read(./.env)`, `Read(./.env.*)`, `Bash(git push --force*)`, `Bash(rm -rf *)`. `settings.local.json`: `{"permissions":{"allow":[]}}`.
- [ ] **Step 6: Verify** — `python -c "import json,glob;[json.load(open(f)) for f in glob.glob('vcare-*/.claude/settings*.json')]"` → no error; each `SKILL.md` starts with `---\nname:` matching its folder.
(No commit here — per spec build order, every repo is committed once in Task 12.)

## Phase 2 — Parallel subagents (dispatch all three in one message)

### Task 7: Identity docs + contract (subagent A)

**Files:** `vcare-identity-api/contracts/openapi.yaml`; `docs/{INDEX,service-card,system-design,runbook,quickstart}.md`; `docs/architecture/{overview,data-model,api,auth-tokens,service-auth,infrastructure,future}.md`; `docs/adr/{0001-no-orm-knex-raw-sql,0002-asymmetric-jwt-rotating-refresh,0003-argon2id-password-hashing}.md`.

- [ ] **Step 1:** Dispatch with the brief: read spec, Global Constraints, Identity `CLAUDE.md`, PRD §4, §5, §6 (Identity), §11, §14, reference notification + with-context docs. Contract: OpenAPI 3.1, servers `/api` + `/internal`, every PRD §14 Identity route + `POST /internal/auth/token` + `GET /.well-known/jwks.json` + `GET /health`; `components.securitySchemes` `bearerUser`, `serviceToken`; `ErrorEnvelope` schema + shared responses; request/response schemas for every route; `x-roles` + `x-ownership` extension on every operation. `service-card.md` frontmatter includes `sync_to_hub: catalog/identity-service.card.md`, links written repo-root-relative (`../contracts/...`, `./INDEX.md`). All docs `status: draft`, frontmatter per Global Constraints. No application code.
- [ ] **Step 2: Verify** — `npx -y @redocly/cli lint vcare-identity-api/contracts/openapi.yaml` → `0 errors`.

### Task 8: Care docs + contract (subagent B)

**Files:** `vcare-care-api/contracts/openapi.yaml`; `docs/{INDEX,service-card,system-design,runbook,quickstart}.md`; `docs/architecture/{overview,data-model,api,scheduling-slots,consultation-lifecycle,clinical-records,rbac,integration,resilience,infrastructure,future}.md`; `docs/adr/{0001-no-orm-knex-raw-sql,0002-slots-never-stored,0003-db-exclusion-constraint,0004-cross-service-failure-policies}.md`.

- [ ] **Step 1:** Dispatch with the brief: as Task 7 but Care `CLAUDE.md`, PRD §3–§13 complete, every PRD §14 Care route + `GET /internal/doctors/{userId}/summary` + `GET /health`; `Idempotency-Key` header required on the three booking operations; runbook alerts include `IdentitySuspensionSyncFailing`, `IdentityHydrationDegraded`, `SlotComputationLatencyHigh`, `ExclusionViolationSpike`; `sync_to_hub: catalog/care-service.card.md`.
- [ ] **Step 2: Verify** — `npx -y @redocly/cli lint vcare-care-api/contracts/openapi.yaml` → `0 errors`.

### Task 9: Hub content (subagent C)

**Files:** `vcare-hub/{CLAUDE.md,INDEX.md,README.md,TODO.md,glossary.md}`; `catalog/service-catalog.md`; `architecture/{landscape,data-ownership}.md`; `adr/{0001-two-service-split,0002-hub-and-spoke-docs,0003-service-token-s2s-auth,0004-numeric-ids-exposed}.md`; `product/prd.md`; `scripts/{sync-from-spoke,check-freshness}.sh`.

- [ ] **Step 1:** Dispatch with the brief: replicate `playground-hub` structure and tone; `product/prd.md` = frontmatter + PRD text copied **verbatim** from `INITIALIZE-VCARE-PROMPT.md` lines 87–320; `INDEX.md` has a "Source of intent" row for the PRD; `landscape.md` C4 L1/L2 (Client, identity-service, care-service, Postgres×2, Redis×2, email provider, video provider, future AI service) + dependency graph + the 3 integration cases with sequence + failure policy; `data-ownership.md` per PRD §6 entities; glossary terms (User, Patient, Doctor, Admin, Account status, Verification, Consultation, Slot, Consultation type, Working hours, Schedule exception, Medical record, Amendment, Service token, Hydration, Degrade vs must-not-degrade, Request id, Idempotency key, Service card, Spoke, Hub); scripts ported from reference with `vcare` examples, `sync-from-spoke.sh` copies only `openapi` (no asyncapi); `check-freshness.sh` scans every `.md` except `README.md`, `CLAUDE.md`, `TODO.md` (so `docs/superpowers/**` is checked — those files carry frontmatter). `chmod +x` scripts. Registry commit to cite anywhere needed: `97184105b5daa3a6860a2aeb8e7e7fd1c42da40a`.
- [ ] **Step 2: Verify** — `bash vcare-hub/scripts/check-freshness.sh` → `OK: all docs fresh and stamped` (before sync, cards absent is fine); `diff <(sed -n '87,320p' INITIALIZE-VCARE-PROMPT.md) <(awk 'f;/^---$/{c++; if(c==2) f=1}' vcare-hub/product/prd.md | sed '1{/^$/d}')` → no output.

## Phase 3 — Registry skills (inline, runs while Phase 2 subagents work)

### Task 10: Install skills.sh skills + lock files

**Files:** `vcare-{identity,care}-api/.claude/skills/<name>/SKILL.md` (19 each); `vcare-{identity,care}-api/skills-lock.json`.

- [ ] **Step 1: Registry commit** — resolved during planning: `97184105b5daa3a6860a2aeb8e7e7fd1c42da40a` (`git ls-remote https://github.com/mindrally/skills HEAD`). None of the 20 skill folders contain files other than `SKILL.md`.
- [ ] **Step 2: Download pinned files** — for each name, `curl -fsSL https://raw.githubusercontent.com/mindrally/skills/<sha>/<name>/SKILL.md -o .claude/skills/<name>/SKILL.md` into each target spoke (shared 18 → both; `oauth-implementation` → Identity; `rabbitmq-development` → Care). If a skill folder contains files besides `SKILL.md`, copy those too.
- [ ] **Step 3: Write `skills-lock.json`** via python: `{"version":1,"registry":"mindrally/skills","registryCommit":"<sha>","hashMethod":"sha256-file","skills":{"<name>":{"source":"mindrally/skills","sourceType":"github","skillPath":".claude/skills/<name>/SKILL.md","computedHash":"<sha256>"}}}`, keys sorted.
- [ ] **Step 4: Verify** — python recomputes every hash and compares to the lock (0 mismatches); count `installed == 19` per spoke; `ls vcare-*/.claude/skills | grep -Ei 'prisma|drizzle|typeorm|sequelize|kysely|nestjs|graphql|grpc|trpc|fastapi|cypress|playwright|auth0|clerk'` → no output.

## Phase 4 — Verify + commit

### Task 11: Sync, freshness, lint, invariants

- [ ] **Step 1: Sync** — `cd vcare-hub && bash scripts/sync-from-spoke.sh identity-service ../vcare-identity-api && bash scripts/sync-from-spoke.sh care-service ../vcare-care-api` → `catalog/{identity,care}-service.card.md`, `contracts/{identity,care}-service.openapi.yaml` exist.
- [ ] **Step 2: Freshness** — `bash scripts/check-freshness.sh` → exit 0.
- [ ] **Step 3: Lint** — `npx -y @redocly/cli lint ../vcare-identity-api/contracts/openapi.yaml ../vcare-care-api/contracts/openapi.yaml contracts/*.yaml` → 0 errors.
- [ ] **Step 4: Invariants** —
  - `cmp contracts/identity-service.openapi.yaml ../vcare-identity-api/contracts/openapi.yaml` and same for care → identical.
  - `grep -rnE 'CLAUDE\.md ?§ ?[0-9]' ../vcare-*/.claude ../vcare-*/CLAUDE.md` → no output.
  - `find .. -path ../vcare-*/.git -prune -o \( -name '*.ts' -o -name package.json -o -name tsconfig.json -o -type d -name src \) -print` from `VCare` → no output.
  - `ls -A "/e/Full Stack Projects/Vcare/VCare"` → exactly the three repo dirs.
  - `test ! -d .claude` in hub.
  - Frontmatter check (python): every non-exempt `.md` in the three repos has all 7 required keys.
- [ ] **Step 5: Fix any failure at its source task, re-run Steps 1–4.**

### Task 12: Commit each repo

- [ ] **Step 1:** In each spoke: `git add -A && git commit -m "docs: add contracts, service docs, ADRs, and pinned skills"` (with attribution lines).
- [ ] **Step 2:** In hub: `git add -A && git commit -m "docs: add hub catalog, contracts, architecture, ADRs, glossary, PRD, and sync scripts"` (with attribution lines).
- [ ] **Step 3: Verify** — `git -C <repo> status --short` → empty for all three; `git log --oneline` shows the commits.
