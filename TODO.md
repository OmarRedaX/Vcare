# Hub — Deferred (TODO)

Things intentionally **not** built yet. Captured here so they're a decision, not a gap.

## CI / automation (deferred — do later)
- [ ] **Docs-lint CI** — a GitHub Actions workflow that runs on every hub PR:
  - `scripts/check-freshness.sh` (frontmatter `last_verified` freshness) — already written, run manually for now.
  - a broken-internal-link check across hub docs (including links rewritten into synced cards).
  - **contract drift**: check out each spoke in CI and `diff` `contracts/<service>.openapi.yaml` here against the spoke's `contracts/openapi.yaml` (fail on drift). Today the sync just copies; there's no automated guard.
- [ ] **Sync trigger** — have each spoke's CI call `scripts/sync-from-spoke.sh` on merge to main and open a hub PR (today it's run manually).

## Platform docs — care-service roll-up rows (ADR 0008)
- [x] **Care capacity** — derived in care-service `docs/architecture/capacity.md`; hub row filled (2026-09-15).
- [x] **Care availability / RPO / RTO** — care ADR 0005 (99.9 %); hub row filled; platform roll-up now 99.9 % (2026-09-15).
- [x] **Care runtime detail** — care-service `docs/architecture/deployment.md`, care ADRs 0006–0008 (2026-09-15).
- [ ] **Placement check in CI** — the `service: platform` ⇔ hub check runs today only in the spokes' Stop hook.

## Events / AsyncAPI (once a message bus exists)
MVP is HTTP-only; there are no event contracts. When an ADR adopts a bus (RabbitMQ is the candidate
named by care-service), add `contracts/<service>.asyncapi.yaml` to the sync and an event-flow table to
`architecture/landscape.md`. Candidate events already named by the spokes:
- [ ] identity-service: `user.registered`, `user.status_changed`
- [ ] care-service: `consultation.booked`, `consultation.cancelled`, `doctor.suspended`

## Known architecture gaps
- [x] **Identity-originated doctor status change** — closed 2026-09-15 by [ADR 0006](./adr/0006-doctor-account-status-via-care-only.md):
  Identity's admin route refuses doctor targets; doctor status changes only through Care.
- [x] **Doctor reinstatement** — designed 2026-09-15 as Case 4 ([ADR 0009](./adr/0009-doctor-reinstatement-via-care.md), care ADR 0012).

## Follow-ups from care-service `/system-design` (2026-09-15) — provider first
- [x] **identity-service `/system-design` or `/construct-spec`:** allow `suspended → active` on
  `PATCH /internal/users/:id/status` for doctors (Case 4, hub ADR 0009); amend identity ADR 0012 and its docs.
- [x] **identity-service:** add `GET /internal/users/contacts?ids=` + scope `users:contact:read` allowed only for
  `care-service` (Case 5, hub ADR 0010); update identity capacity for the extra internal load (≈ 25 k rows/day →
  ≈ 1–2 k calls/day, negligible).
- [x] **`/system-design` for identity service-auth (P-1, 2026-10-08):** recorded 2026-10-09 in `architecture/landscape.md` (token refresh 30 s before expiry as built, secret manager and rotation) and `architecture/deployment.md` (`INTERNAL_TRUST_PROXY_HOPS >= 1`). The ~60 s margin in the original item was not what Care built.
- [x] **care-service: `Retry-After` on Identity `429`** (2026-10-09): decided — own-backoff is the platform rule; no Care change. Recorded in `landscape.md`.
- [x] **Re-sync both spokes** (`scripts/sync-from-spoke.sh`) after the contract changes land (care: health
  live/ready, reinstate endpoint, audit-log time range).
- [x] **Glossary:** add "care-worker", "notification outbox", "Case 4 / Case 5" (2026-10-09).
- [x] **care-service file handling — contract and code** (care ADRs 0013–0015 and 0022, hub ADR 0011): built for verification
  documents (2026-10-08) and record attachments (2026-10-20); contract synced (uploads + complete, download-url, DTOs without
  `downloadUrl`, `UploadIntentExpired`, `AttachmentLimitReached`).
- [ ] **care-service file handling — bucket IaC and web CSP** (decided 2026-10-20, `/system-design`; derivation in care
  `docs/architecture/file-handling.md`): the bucket module must name **both final prefixes**, `verification-documents/*` and
  `record-attachments/*`, wherever it names a prefix:
  - Block Public Access on, TLS-only bucket policy, SSE-S3 (unchanged for clinical attachments), CORS `POST` from the web origin only.
  - Lifecycle: `quarantine/*` expires after 24 h; `verification-documents/*` **and `record-attachments/*`** move to infrequent access after 90 days.
  - IAM, `care-api` task role: `s3:PutObject` for presigned POST on `quarantine/*` only; `s3:GetObject` and `s3:CopyObject` source/target
    on `quarantine/*` and both final prefixes (presigned GET, byte-range read and promote); `s3:DeleteObject` on `quarantine/*` and on
    the final prefixes (rollback cleanup of a promoted object).
  - IAM, `care-worker` task role: `s3:ListBucket` and `s3:DeleteObject` on `quarantine/*` (upload-intent purge).
  - The web app's CSP (`form-action`/`connect-src` for the bucket host).
- [ ] **Availability:** revisit Care synchronous standby (99.95 %) — the platform is capped at 99.9 % by care ADR 0005.

## Follow-ups from identity-service `/system-design` (2026-09-15)
- [x] **PRD §14 appendix** (2026-10-11) — replaced `POST /auth/register`, `/auth/verify-email`,
  `/auth/resend-verification` with `POST /auth/register/start` and `/auth/register/complete`
  (identity-service ADR 0006). PRD prose updated 2026-10-12: `EmailVerification` entity -> `RegistrationChallenge`, and the
  "verify email" steps in §7.1 and flow A (verification is now proven before the account exists).
  (identity-service ADR 0006).
- [x] **Re-sync identity-service** — baseline contract changes (ADRs 0004/0005/0006/0012) applied and synced
  2026-09-16. Cases 4 and 5 (above) still need their own identity contract change and re-sync.
- [x] **Spoke alignment** — both spokes' `CLAUDE.md` and `rbac-ownership-guard` skills updated for ADRs 0005/0006
  and identity-service ADRs 0004–0014 (2026-09-15).
- [ ] **PII erasure** (pre-GA, not MVP) — identity-service keeps PII on soft delete (its ADR 0011); design in identity `docs/architecture/future.md` §7; revisit before GA.
- [ ] **Admin MFA** (pre-GA, not MVP) — first post-MVP security item (identity-service ADR 0010); design in identity `docs/architecture/future.md` §2.
- [ ] **`doctors:read` consumer** — the scope and Care's `/internal/doctors/:userId/summary` exist, but no
  service client holds the scope in MVP. Provision one when admin tooling or the Phase-2 AI service needs it.

## Phase-2 AI & Retrieval service onboarding
- [ ] New row in `catalog/service-catalog.md` (currently "planned") and a spoke repo with `docs/service-card.md` + `contracts/openapi.yaml`, then run the sync.
- [ ] A service client in Identity (`service_clients`) with its own allowed scopes.
- [ ] Define the Care internal endpoints and scopes its tools need (`searchDoctors`, `getAvailableSlots`, `bookConsultation`, `rescheduleConsultation`) — provider contract lands first in care-service.
- [ ] Overview row and C4 node, deployment components and availability row, capacity roll-up row, landscape node, data-ownership rows (vector store, AI drafts), glossary terms.

## Discoverability
- [ ] Semantic search / **docs-MCP** over the hub corpus. The `INDEX.md` router is the retrieval mechanism until volume forces it.

## Glossary / ownership upkeep
- [ ] Keep `glossary.md` and `architecture/data-ownership.md` rolled up as modules are built and services are added.
