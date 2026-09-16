---
title: vcare Data-Ownership Map
owner: platform-team
service: platform
status: stable
diataxis: explanation
last_verified: 2026-09-15
tags: [architecture, data-ownership, boundaries, privacy]
related: [prd, landscape, glossary, adr-0001-two-service-split, adr-0006-doctor-account-status-via-care-only, adr-0011-object-storage-host]
---

# Data-Ownership Map

The single-writer rule for the whole platform: **exactly one service owns (writes) each piece of
data.** Everyone else reads it via that service's API — never its database. This is what keeps the
split a real two-service architecture and not a distributed monolith. Entities come from
[PRD §6](../product/prd.md).

## identity-service
| Data domain | Owner (single writer) | Others access via | Notes |
|---|---|---|---|
| Users — email, phone, password hash, role, email-verified timestamp | identity-service | access-token claims (`sub`, `role`, `ev`); admin `GET /api/users`; `GET /internal/users/contacts?ids=` (email only, planned) | email leaves Identity only through the contacts lookup to `care-worker` for delivery, never stored by Care ([ADR 0010](../adr/0010-notification-contact-lookup.md)); phone never leaves Identity through `/internal/*`; password hash never leaves Identity at all |
| Users — profile display fields: full name, avatar, timezone, locale | identity-service | `GET /internal/users?ids=` (Case 2) | names/avatars: Care hydrates via Case 2, caches ≤ 300 s, never stores |
| Account status (`pending`, `active`, `suspended`, `rejected`) | identity-service | token `status` claim; `GET /internal/users?ids=` | account status: Identity writes; Care requests changes via Case 1/3 (`PATCH /internal/users/:id/status`); for **doctors** Care is the only initiator — Identity's admin route refuses doctor targets ([ADR 0006](../adr/0006-doctor-account-status-via-care-only.md)) |
| Account status history (`user_status_changes`) | identity-service | not exposed to other services | who changed a status, when, why, from which service; written in the same transaction as the change |
| Refresh tokens (families, rotation, revocation) | identity-service | not exposed | stored only as hashes; revoked on suspension/rejection, password change/reset |
| Password resets | identity-service | not exposed | hashed single-use tokens, 30 min |
| Registration challenges (email-ownership codes) | identity-service | not exposed; outcome visible as token `ev` claim | HMAC-peppered 6-digit codes, 10 min, 5 attempts; accounts are created already verified (replaces email verifications, identity-service ADR 0006) |
| Outbox jobs (email delivery, future events) | identity-service | not exposed | ids only — no PII or secrets; processed by `identity-worker` (identity-service ADR 0007) |
| Service clients (id, secret hash, allowed scopes) | identity-service | `POST /internal/auth/token` | secrets hashed with argon2id |
| JWT signing keys | identity-service | `GET /.well-known/jwks.json` (public keys only) | private keys come from a secret store, never the database or repo |

## care-service
| Data domain | Owner (single writer) | Others access via | Notes |
|---|---|---|---|
| Doctor profiles (headline, bio, experience, languages, fee, currency, slot length, timezone, accepting flag) | care-service | `GET /api/doctors`, `/api/doctors/:id` | keyed by Identity user id (`BIGINT`, no FK) |
| Doctor verification status, local suspension state, identity sync status | care-service | `GET /internal/doctors/:userId/summary` | the verification *decision* is Care's; the resulting *account status* is Identity's |
| Verification documents and decisions | care-service | admin application endpoints; on-demand `download-url` | stored by object key only after Care verifies the uploaded bytes; downloads are presigned GETs valid 60 s, issued per click and audited (care ADRs 0013–0014, [ADR 0011](../adr/0011-object-storage-host.md)) |
| Specialties | care-service | `GET /api/specialties` | admin-managed |
| Doctor ↔ specialty links | care-service | doctor profile and search endpoints | one marked primary |
| Working hours | care-service | slot endpoints (computed) | wall-clock `TIME` + doctor IANA timezone |
| Schedule exceptions | care-service | slot endpoints (computed) | blocking booked time flags consultations, never auto-cancels |
| Consultation types | care-service | doctor profile and slot endpoints | duration and price per type; money in minor units + currency |
| Slots | nobody — **never stored** | `GET /api/doctors/:id/slots` | computed per request; Redis cache of a computed window is derived (TTL ≤ 60 s) |
| Consultations | care-service | consultation endpoints (patient, assigned doctor, admin) | exclusion constraint prevents overlaps; complaint text is clinical data |
| Patient profiles (demographics, allergies, chronic conditions, blood type, timezone) | care-service | `GET /api/patients/me`, `/api/patients/:id` (self or consulting doctor) | clinical data: never leaves Care except to the patient and consulting doctor |
| Medical records | care-service | record endpoints (patient, assigned/consulting doctor) | clinical data: never leaves Care except to the patient and consulting doctor; admins never read; every access audited |
| Medical record amendments | care-service | record endpoints | append-only after the 24 h lock |
| Record attachments | care-service | on-demand `download-url` (patient, consulting doctor; never admins) | stored by object key only after byte verification; presigned GET 60 s, audited; no delete after lock |
| Upload intents | care-service | not exposed | temporary (15 min), single-use; never a document or attachment |
| Help articles | care-service | `GET /api/help-articles` | Phase-2 RAG corpus (read by the AI service through Care's API) |
| Audit log | care-service | `GET /api/audit-logs` (admin, metadata only) | append-only, monthly partitions, retained ≥ 6 years; metadata never holds clinical text or PII |
| Notification outbox | care-service | not exposed | ids and non-clinical render params only — no email, no clinical text; delivered by `care-worker` (care ADR 0011) |
| Identity sync jobs (Cases 1, 3, 4) | care-service | not exposed | ids, target status, error class only |

## Derived and borrowed data (not owned)
| Data | Held by | Source of truth | Rule |
|---|---|---|---|
| Hydrated user display fields (`identity:user:<id>`) | care-service Redis | identity-service | TTL 300 s; never copied into Care tables |
| JWKS public keys | care-service memory | identity-service | refreshed on unknown `kid`, at most once per minute |
| Recipient email for a notification batch | `care-worker` memory only | identity-service | fetched at send time; never cached, persisted, or logged |
| Service token | care-service memory | identity-service | cached until 30 s before its 300 s expiry |
| Idempotency records | each service's own Redis | the service that received the write | 24 h; Care also persists the booking key on the consultation row |
| `next_available_at`, computed slot windows | care-service Redis | care-service inputs | derived, TTL-bound, invalidated on input change |

## Rules
1. **One writer per piece of data.** If two services want to write the same data, the boundary is
   wrong — the other service *requests* the change through the owner's internal API.
2. **No cross-service DB reads.** Borrow data via the owner's API (and, once a bus exists, events).
   No shared database, no read replica of another service's schema.
3. **Borrowed data is cached briefly, not stored.** Care shows a doctor's name from a ≤ 300 s cache,
   never from its own column.
4. **Ids referenced across services are numeric Identity user ids without foreign keys**
   (`user_id` / `<role>_user_id BIGINT`, commented "Identity user id"). Referential integrity across
   services is a runtime concern (unknown ids are omitted by hydration), not a database constraint.
   See [ADR 0004](../adr/0004-numeric-ids-exposed.md).
5. **Clinical data stays in Care** and is never logged, never put in audit metadata, and never
   returned to admins.

## Aggregated from
Each service declares what it owns in its `CLAUDE.md` ("Mission of this service") and
`docs/architecture/data-model.md`; this map is the platform-wide roll-up, updated by a spoke's
`/system-design` for cross-service topics.
