---
title: vcare Glossary (Ubiquitous Language)
owner: platform-team
service: platform
status: stable
diataxis: reference
last_verified: 2026-09-15
tags: [glossary, ubiquitous-language, terminology]
related: [prd, overview, data-ownership, landscape, adr-0008-doc-placement-by-scope]
---

# Glossary — Ubiquitous Language

One definition per term, shared by every service, human, and AI agent. If code, docs, and
conversation all use these words the same way, cross-service reasoning stays consistent. Add a term
here **before** it spreads with three different meanings.

## Accounts and access
| Term | Definition | Owned by |
|---|---|---|
| **User (account)** | An authenticated account: email, phone, password hash, full name, avatar, role, account status, timezone, locale. Identified by a numeric user id that other services reference without a foreign key. | identity-service |
| **Role** | One of `patient`, `doctor`, `admin`. Set at registration (`patient` or `doctor` only); admins are created manually by ops in the identity database and set their own password through password reset (identity-service ADR 0010). Carried in the access token. Authorization policies name allowed roles explicitly — there is no "any authenticated user" wildcard. | identity-service |
| **Account status** | `pending` (doctor awaiting verification), `active`, `suspended`, `rejected`. The source of truth for whether an account may act; carried in the access token. Only valid transitions are allowed. | identity-service |
| **Patient** | A User with role `patient`. Books consultations and reads their own history. Clinical profile data lives in the Patient profile. | identity-service (account) / care-service (profile) |
| **Doctor** | A User with role `doctor`: an independent practitioner. Bookable only once verified, active, and accepting patients. | identity-service (account) / care-service (profile) |
| **Admin** | A User with role `admin`: platform staff who review applications, suspend doctors, manage specialties and help content, and act on bookings on a user's behalf — never read clinical notes. | identity-service |
| **Access token** | A 15-minute EdDSA-signed JWT (`typ=user`) with `sub`, `role`, `status`, `ev` (email verified). Verified locally by every service against the JWKS; sent as `Authorization: Bearer`. Issued for `pending`, `active`, and `rejected` accounts, never `suspended`; `ev` is always true for accounts created by email-first registration. | identity-service |
| **Refresh token** | An opaque 30-day token in an httpOnly cookie, stored only as a hash. **Rotating**: every use revokes it and issues a successor in the same **family**. **Reuse detection**: presenting an already-rotated token revokes the whole family — except within the **grace window**. | identity-service |
| **Grace window** | The 10 seconds after a refresh-token rotation during which re-presenting the old token (while its successor is unused) returns `401 RefreshTokenInvalid` without revoking the family or clearing the cookie, so concurrent refreshes from several tabs do not log the user out. | identity-service |
| **Registration challenge** | The email-ownership proof in email-first registration: `register/start` sends a 6-digit code (10 min, 5 attempts); `register/complete` with the code creates an already-verified account. Start always answers `202`, so it never reveals whether an email is registered. | identity-service |
| **Service client** | A registered calling service (`client_id`, argon2id-hashed secret, allowed scopes) permitted to request service tokens. | identity-service |
| **Service token** | A 300-second JWT (`typ=service`, `sub=<client_id>`, `aud`, `scope`) obtained with client credentials at `POST /internal/auth/token`. The only credential accepted on `/internal/*`. No refresh token. | identity-service |
| **Scope** | A named permission inside a service token: `users:read`, `users:status:write`, `doctors:read`. Requested scopes must be a subset of the service client's allowed scopes. | identity-service |
| **Internal endpoint** | A route under `/internal/*`, served on a separate private listener, never routed by the public ingress, requiring a service token. A user token — even an admin's — gets `401 ServiceTokenRequired`. | the providing service |

## Doctors and scheduling
| Term | Definition | Owned by |
|---|---|---|
| **Doctor profile** | Care's record of a doctor: headline, bio, experience, languages, fee and currency, default slot length, timezone, verification status, accepting-patients flag, local suspension state, identity sync status. Keyed by the Identity user id. | care-service |
| **Verification** | The credentialing process. The **application** moves `draft → submitted → approved \| rejected` (and `rejected → submitted` when re-opened, which also returns the Identity account to `pending`); the **decision** is the admin's approve/reject with reviewer and note. Documents (license, ID, degree) are part of it. | care-service |
| **Specialty** | A medical specialty (name, slug, description) managed by admins; doctors link to one or more, one marked primary. | care-service |
| **Working hours** | A doctor's recurring weekly availability (weekday, start time, end time) as wall-clock times in the doctor's IANA timezone; split shifts allowed. | care-service |
| **Schedule exception** | A date-specific override of working hours: `day_off` or `custom_hours`, with a reason. Blocking time that holds bookings must be confirmed and flags those consultations. | care-service |
| **Consultation type** | A doctor-defined offering (e.g. first visit, follow-up) with its own duration and price. Duration always comes from here. | care-service |
| **Slot** | A bookable interval **computed per request**: working hours − schedule exceptions − booked consultations, sliced by consultation-type duration in the doctor's timezone, rendered in the patient's timezone. **Never stored**; only a short-lived derived cache is allowed. | care-service |

## Consultations and records
| Term | Definition | Owned by |
|---|---|---|
| **Consultation** | A booked appointment between one patient and one doctor for one consultation type, with UTC `starts_at`/`ends_at`, complaint text, and a lifecycle status. Overlaps for a doctor are impossible at the database level. | care-service |
| **Consultation lifecycle states** | `booked → waiting → in_progress → completed`, with `cancelled` and `no_show` as terminal exits. Terminal states (`completed`, `cancelled`, `no_show`) never change. | care-service |
| **Policy window** | The period before start (default 2 hours) inside which a patient may not cancel or reschedule. Admins are not restricted. | care-service |
| **Grace period** | Time after start (default 10 minutes) before a consultation may be marked `no_show`. | care-service |
| **Session window** | When the video room is open: from 10 minutes before start to 15 minutes after the scheduled end. Join and start are rejected outside it. | care-service |
| **Medical record** | The structured clinical record of a `completed` consultation (chief complaint, examination notes, diagnosis text and code, treatment plan, follow-up interval). One per consultation; written only by the assigned doctor; locked 24 hours after creation. | care-service |
| **Amendment** | An append-only correction to a medical record after its 24-hour lock. The original is never overwritten. | care-service |
| **Record attachment** | A file attached to a medical record, stored by object key (never a public URL); cannot be deleted after the lock. | care-service |
| **Presigned URL** | A short-lived object-storage URL issued by the owning service after an authorization check: a presigned POST (5 minutes, fixed key and size range) to upload into quarantine, or a presigned GET (60 seconds, forced download, audited) to open a verification document or record attachment. A bearer link — never logged or stored (ADR 0011). | care-service |
| **Upload intent** | A temporary (15-minute), single-use permission to upload one file, bound to its owner and target. It is not a document or attachment: the real row is created only when `complete` verifies the stored object's size and leading bytes. | care-service |
| **Help article** | Published help content (title, body, category, audience `patient`/`doctor`). The Phase-2 RAG corpus. | care-service |
| **Audit log** | Append-only rows (actor, role, action, entity, request id, metadata) for every clinical access, status change, verification decision, suspension, and admin action on behalf of a user. Metadata never holds clinical text or PII. | care-service |

## Cross-service integration
| Term | Definition | Owned by |
|---|---|---|
| **Hydration** | Filling display fields (full name, avatar) for a page of Identity user ids with **one** batched `GET /internal/users?ids=` call (≤ 100 ids), read-through a 300-second cache. Integration Case 2. | care-service (consumer) / identity-service (provider) |
| **Degrade vs must-not-degrade** | The two opposite failure policies. **Degrade**: on provider failure, serve what you have and never fail the request (Case 2). **Must-not-degrade**: never report success until the provider confirms; retry durably and alert (Case 3). Case 1 sits between: keep the decision, retry, report pending. | platform |
| **Identity sync status** | Care's per-doctor marker (`pending` / `synced` / `failed`) of whether Identity has confirmed the account-status change Care requested (Cases 1 and 3); `failed` means Identity rejected the transition as invalid (drift) and a human must resolve it. A doctor is bookable only when approved **and** synced. | care-service |
| **Request id** | A UUID in `X-Request-Id`, accepted or generated at the edge, echoed on every response, forwarded on every internal call, and written on every log line and audit row, so one trace spans both services. | platform |
| **Idempotency key** | A client-supplied UUID in `Idempotency-Key` that makes a repeated write a no-op: same key + same body replays the original response; same key + different body → `422 IdempotencyConflict`. Required on registration and on booking, reschedule, and cancel. | platform |
| **Error envelope** | The one error shape shared by both services: `{ "success": false, "error": { "code", "message", "details?", "requestId" } }`. Error codes are PascalCase and stable forever. | platform |
| **Edge** | The CDN + WAF in front of the single public origin; it routes `/api/*` path prefixes to the owning service and never routes `/internal/*` or health endpoints (ADR 0005). | platform |
| **Outbox** | A table written in the same transaction as a business change, holding jobs (email sends, later events) that a separate worker processes at least once. Rows hold ids only, never PII or secrets. | each service (identity-service first) |

## Documentation
| Term | Definition | Owned by |
|---|---|---|
| **Service card** | The one-page cross-cutting summary of a service (`docs/service-card.md` in the spoke), synced into `catalog/<service>.card.md`. | platform |
| **Spoke** | A service repo that owns its code, its docs, its contract, and its `.claude/` workflow (`vcare-identity-api`, `vcare-care-api`). | platform |
| **Hub** | This repo — every platform-scope doc (overview, deployment, capacity, landscape, data ownership, glossary, platform ADRs, PRD) plus synced service cards and contracts. No application code, no `.claude/`. | platform |
| **Platform scope** | A doc or fact true of the platform as a whole or of two or more services, or one that another service, ops, or product must agree on without reading one service's code. Lives only in the hub; frontmatter `service: platform` (ADR 0008). | platform |
| **Service scope** | A doc or fact made true only by one service's code (modules, data model, configuration, its sizing derivation, its alerts). Lives only in that service's `docs/`. | platform |
| **Roll-up** | The hub's one-row-per-service summary inside a split topic (capacity, deployment, availability, data ownership): headline values quoted with a link to the service doc where they are derived. Each number is authored once. | platform |

## Deliberate distinctions
- **User vs Patient/Doctor profile** — a User is the *account* (credentials, role, status, name) in
  Identity; a Patient profile or Doctor profile is the *domain data* in Care, keyed by the user id.
  Care never stores passwords or names long-term; Identity never stores allergies or fees.
- **Slot vs Consultation** — a Slot is a *possibility* computed on demand and never persisted; a
  Consultation is a *commitment* stored with an exclusion constraint. Booking turns one Slot into one
  Consultation, and the slot must still be free at that moment.
- **Verification decision (Care) vs Account status (Identity)** — Care owns the medical judgment
  ("this licence is valid"); Identity owns the account state that gates access ("this account may act
  as a doctor"). Approving writes the decision in Care, then asks Identity to set `active` (Case 1).
- **Record update vs Amendment** — within 24 hours of creation the assigned doctor may update a record
  in place (audited); after the lock every correction is a new Amendment and the original is untouched.
