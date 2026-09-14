---
title: Virtual Care Platform — PRD (MVP v1.0)
owner: platform-team
service: platform
status: approved
diataxis: explanation
last_verified: 2026-09-14
tags: [prd, product, requirements]
related: [landscape, data-ownership, glossary]
---

# Virtual Care Platform
## Product Requirements Document — MVP v1.0

## 1. Product vision
Getting a doctor's appointment means calling clinics one by one, asking who's available, and traveling for what is often a 10-minute conversation. Doctors, meanwhile, have no way to sell their time outside a physical practice. This platform connects patients to **independent doctors for online consultations**. Patients search by specialty, language, price, or availability, book a slot, and meet by video. Doctors set their own hours and pricing and keep a structured record of every consultation. It is a **network, not a clinic**: thousands of independent practitioners, millions of patients, no shared physical location.

## 2. Business goals
| Goal | Measure of success |
|---|---|
| Make discovery fast | Patient books within 3 minutes of landing |
| Fill doctor calendars | ≥60% slot utilization for active doctors |
| Keep quality high | Only verified, licensed doctors can accept bookings |
| Reduce no-shows | No-show rate tracked per doctor and per patient |
| Make records portable | Every completed consultation has a structured record the patient can access |

## 3. Users
**Patient** — searches for doctors, books consultations, joins the video session, reads their own history.
**Doctor** — an independent practitioner. Applies to join, gets verified, sets availability and pricing, consults, writes the medical record.
**Admin** — platform staff. Reviews and approves doctor applications, suspends accounts, manages specialties and help content, and intervenes on bookings when something goes wrong (reschedules or cancels on a user's behalf).
> Doctors are **independent** — nobody schedules for them. Admins act on a user's behalf only to resolve problems, and never see clinical notes.

## 4. System overview
Two independently deployable services, each with its own database.
### 4.1 Identity & Access Service
Owns **who someone is and whether they may act**: accounts, authentication, roles, sessions, email verification, password management, account status.
### 4.2 Care Service
Owns **the medical marketplace**: doctor profiles and credentials, specialties, schedules, consultations, video sessions, medical records, help content.
### 4.3 Why the split is necessary at this scale
| Dimension | Identity | Care |
|---|---|---|
| **Traffic shape** | Login and token refresh — huge volume, tiny payloads, read-dominated | Search, slot computation, booking — heavy queries and writes |
| **Scaling trigger** | Total registered users | Active consultations and search volume |
| **Peak pattern** | Steady, spiky at campaigns | Evening peaks, when people book |
| **Data sensitivity** | Credentials | Medical records — different retention, audit, and encryption rules |
| **Consumers** | Every service, now and future | Patients and doctors |

Identity is the shared foundation: the Phase 2 AI service authenticates against it too, without touching Care's database. Care never stores a password, never issues a token, and holds only `user_id` references.
### 4.4 Authorization (no network call per request)
Identity issues a signed JWT — short-lived access token plus rotating refresh token — carrying `user_id`, `role`, and `status`. Care validates it locally using the shared public key. At this traffic level, calling Identity on every request would make it a single point of failure for the entire platform.
### 4.5 Service-to-service authentication
Care holds `SERVICE_CLIENT_ID` / `SERVICE_CLIENT_SECRET`, exchanges them at Identity for a short-lived scoped service token, and sends it as a bearer token on internal calls. Internal routes are network-isolated and reject user tokens. Anti-patterns, stated explicitly: **no shared database**, no static forever-key, never trust a caller-supplied `X-User-Id` header.

## 5. Inter-service integration — the real cases
### Case 1 — Verification unlocks the account *(Care → Identity, synchronous, required)*
A doctor signs up and uploads their **medical license and ID**. Those documents and the credentialing decision belong to Care — professional and medical data, not authentication data. But the *account state* lives in Identity. Until an admin approves, the doctor must not be able to accept bookings. When an admin approves in the Care admin console:
1. Care records the verification decision on the doctor profile
2. Care calls `PATCH /internal/users/:id/status` on Identity → `active`
3. Identity updates the account; the doctor's next token carries active doctor privileges
**Neither service can do this alone.** Care owns the medical judgment; Identity owns the account state that gates access. Rejection follows the same path with `rejected`.
### Case 2 — Batch profile hydration on every listing *(Care → Identity, synchronous, batched, cached)*
A patient searches "dermatologist, Arabic, evenings" and gets 50 doctors. Care stores only `user_id` — names, photos, phone, and email live in Identity. Care collects the IDs and makes **one** call: `GET /internal/users?ids=1,2,3,…`
**Rules:** Always batch — one call per row is an N+1 problem *across a network*, and at search volume it would take Identity down. Cache with a short TTL; names change far less often than search runs. **Degrade, never fail:** if Identity is unreachable, search still returns doctors, slots, and prices — only the display name falls back. Booking must never break because Identity is slow. The same batch call serves search results, the consultation list, and a doctor's patient list.
### Case 3 — Suspension must revoke sessions immediately *(Care → Identity, synchronous, security-critical)*
An admin suspends a doctor for a policy violation. Two things must happen, in two services:
1. Care stops all future bookings and flags upcoming consultations for admin follow-up
2. Care calls `PATCH /internal/users/:id/status` → `suspended`, and Identity **revokes all refresh tokens** so existing sessions die
**This one must not degrade.** If Identity is unreachable, the suspension **fails and is retried**, with an alert — a suspended doctor holding a live session is a real safety problem.
> Cases 2 and 3 use the same mechanism with **opposite failure policies**: one degrades gracefully, one must not. That distinction is the core lesson in cross-service design.
### Internal API surface
**Identity exposes:** `GET /internal/users?ids=1,2,3` (batch profile lookup); `PATCH /internal/users/:id/status` (active | suspended | rejected — revokes sessions).
**Care exposes:** `GET /internal/doctors/:userId/summary` (verification state and specialty, for admin tooling).
All internal endpoints require a service token and are unreachable from the public internet.

## 6. Entities
### Identity Service
| Entity | Key attributes |
|---|---|
| **User** | email, phone, password_hash, full_name, avatar_url, role (patient/doctor/admin), status (pending/active/suspended/rejected), email_verified_at, timezone, locale |
| **RefreshToken** | user_id, token_hash, expires_at, revoked_at, device_info |
| **PasswordReset** | user_id, token, expires_at, used_at |
| **EmailVerification** | user_id, token, expires_at, verified_at |
### Care Service
| Entity | Key attributes |
|---|---|
| **DoctorProfile** | user_id, headline, bio, years_experience, languages, consultation_fee, currency, default_slot_minutes, timezone, verification_status, is_accepting_patients |
| **VerificationDocument** | doctor_id, type (license/id/degree), file_url, status, reviewed_by, review_note |
| **Specialty** | name, slug, description |
| **DoctorSpecialty** | doctor_id, specialty_id, is_primary |
| **WorkingHours** | doctor_id, weekday, start_time, end_time |
| **ScheduleException** | doctor_id, date, type (day_off/custom_hours), start_time, end_time, reason |
| **ConsultationType** | doctor_id, name (first visit/follow-up), duration_minutes, price |
| **Consultation** | doctor_id, patient_id, type_id, starts_at, ends_at, status, complaint_text, patient_timezone, room_id, joined_at, cancel_reason, cancelled_by |
| **PatientProfile** | user_id, date_of_birth, gender, blood_type, allergies, chronic_conditions, timezone |
| **MedicalRecord** | consultation_id, patient_id, doctor_id, chief_complaint, examination_notes, diagnosis_text, diagnosis_code, treatment_plan, follow_up_in_days |
| **RecordAttachment** | record_id, file_url, file_type, description |
| **HelpArticle** | title, body, category, audience (patient/doctor), is_published |
| **AuditLog** | actor_user_id, action, entity_type, entity_id, metadata |

**Slots are never stored.** Availability is computed per request: WorkingHours − ScheduleExceptions − booked Consultations, sliced by consultation type duration, in the **doctor's timezone**, then rendered in the **patient's timezone**.

## 7. Functional requirements
**7.1 Doctor onboarding** — sign up, verify email, complete profile (bio, specialties, languages, experience), upload license and ID, submit for review, track application status. Cannot receive bookings until verified.
**7.2 Verification (Admin)** — queue of pending applications, view documents, approve or reject with a reason *(Integration Case 1)*, re-open a rejected application.
**7.3 Doctor schedule & pricing** — set recurring weekly hours in own timezone, including split shifts; block dates for leave; override hours for a single date; define consultation types with duration and price; toggle "not accepting new patients." *Blocking time that already holds bookings must warn and list the affected consultations before confirming.*
**7.4 Discovery (Patient)** — search doctors by specialty, name, language, price range, and availability window; sort by earliest availability, price, or experience; view a doctor's profile with next available slots.
**7.5 Booking (Patient)** — pick doctor → consultation type → slot (shown in the patient's timezone) → describe the complaint in free text → confirm. *The slot must still be free at the moment of confirmation, and a repeated submission must not create two bookings.*
**7.6 Managing consultations** — patient views upcoming and past, reschedules, cancels; doctor views day and week schedule and cancels with a reason; admin reschedules or cancels on behalf of either party with a recorded reason.
**7.7 The consultation session** — patient joins a waiting room from a set time before start; doctor sees who is waiting and starts the session; both join the video room; doctor ends the session; no-show can be marked after a grace period.
**7.8 Medical records (Doctor)** — record chief complaint, examination notes, diagnosis (text + code), treatment plan, follow-up interval; attach files; view the patient's full timeline including allergies and chronic conditions; book the follow-up directly from the record.
**7.9 Patient profile** — maintain demographics, allergies, chronic conditions, timezone; read own consultation history and records; never edit clinical fields.
**7.10 Help center (Admin)** — publish articles by category and audience: how the platform works, preparing for a consultation, cancellation policy, platform rules. *This is the Phase 2 RAG corpus.*
**7.11 Notifications** — booking confirmation, reminder before start, reschedule, cancellation, "your doctor has joined." Email in MVP, sent asynchronously; delivery failure never blocks a booking.
**7.12 Audit** — every status change, verification decision, suspension, and record edit logged with actor, timestamp, and entity.

## 8. Business rules
**Scheduling**
1. A doctor can never have two overlapping consultations
2. Bookings must fall inside the doctor's working hours for that date, evaluated in the doctor's timezone
3. No booking in the past; maximum booking horizon 60 days
4. Duration comes from the consultation type, not a global constant
5. Booking is transactional and idempotent — concurrent attempts on one slot must not both succeed, and a duplicate submission must not double-book
**Eligibility**
6. Only `verified` + `active` + `accepting` doctors appear in search or accept bookings
7. A suspended doctor's future consultations are flagged for admin follow-up; no new bookings are possible
8. Patients must have a verified email before booking
**Lifecycle** — `booked → waiting → in_progress → completed`, with `cancelled` and `no_show` as terminal exits.
9. Terminal states cannot be changed
10. Patients cancel or reschedule only outside the policy window (default 2 hours before start); admins have no such restriction
11. `no_show` can only be set after start time plus the grace period
12. The video room opens only within the session window
**Clinical**
13. A medical record exists only for a `completed` consultation
14. Only the assigned doctor can write that record
15. Records are append-only after 24 hours — a correction creates an amendment, never a silent overwrite
16. Patients read their own records; they never write clinical fields
**Access**
17. Patients access only their own consultations, records, and profile
18. Doctors access their own schedule and the records of patients they have consulted
19. Admins manage verification, suspension, bookings, and help content — **never clinical notes**
**Data**
20. All timestamps stored in UTC; every user has a timezone and sees their own
21. All list endpoints paginated and filterable
22. Soft delete for profiles and records; hard delete is never exposed

## 9. Permissions matrix
| Capability | Patient | Doctor | Admin |
|---|:--:|:--:|:--:|
| Search doctors | ✅ | — | ✅ |
| Book own consultation | ✅ | — | — |
| Reschedule / cancel on behalf | — | — | ✅ |
| Manage own schedule & pricing | — | ✅ | — |
| Join session | ✅ own | ✅ own | — |
| Write medical record | — | ✅ own | — |
| Read clinical records | own | ✅ consulted | — |
| Approve / reject doctor applications | — | — | ✅ |
| Suspend accounts | — | — | ✅ |
| Manage specialties & help articles | — | — | ✅ |

## 10. Core flows
**A. Doctor onboarding** — sign up → verify email → complete profile → upload license → submit → admin reviews → **approval triggers Integration Case 1** → account activated → doctor sets hours and pricing → appears in search.
**B. Patient discovery & booking** — search by specialty and language → compare price and earliest availability → open profile → pick consultation type → view slots in own timezone → describe complaint → confirm → `booked` + confirmation email.
**C. The consultation** — patient joins the waiting room → doctor sees the queue and starts → video session → doctor writes the record with diagnosis and plan → optionally books the follow-up → `completed`.
**D. Reschedule** — check the policy window → show alternative slots → move atomically, releasing the old slot → notify both sides.
**E. Cancellation** — patient cancels outside the window, doctor cancels with a reason, or admin cancels at any time → slot released → both parties notified.
**F. Doctor takes leave** — blocks a date range → system lists conflicting consultations → doctor confirms → those are flagged for admin follow-up → affected patients notified.
**G. Suspension** — admin suspends a doctor → **Integration Case 3** revokes sessions immediately → future bookings blocked → upcoming consultations flagged for the admin to move or cancel.

## 11. Non-functional requirements
- **Security** — argon2/bcrypt password hashing; short-lived access tokens with rotating refresh tokens; role and ownership enforced on every endpoint; no clinical data in logs; signed, expiring URLs for documents and attachments
- **Privacy** — every access to clinical records is audited; all seed and demo data is fully synthetic
- **Consistency** — booking, reschedule, and cancel are transactional, protected by a database-level exclusion constraint on overlapping consultations, and idempotent on a client-supplied key
- **Resilience** — internal calls time out at 2s with retry and backoff; Case 2 degrades to cached profiles; Case 3 must not degrade — it retries until it succeeds and raises an alert
- **Scale** — search and slot computation are the hot paths: indexed search fields, cached availability windows, read replicas for discovery, rate limiting on public search, pagination everywhere
- **Validation** — validation at the DTO boundary; one consistent error envelope across both services
- **Testing** — unit tests on every rule in §8; e2e tests on flows A, B, C, D, G
- **Schema** — every change ships as a migration
- **Observability** — structured logs with a request ID propagated across services; health endpoint per service
- **Performance** — search results under 400ms; two-week slot computation under 300ms

## 12. Phase 2 — AI capabilities
Delivered as a **third service** (AI & Retrieval): different dependencies (vector store, model providers), different cost profile (per-token), different scaling behavior. Its tools call Care's internal API using the same service-token flow from §4.5 — so Phase 2 **adds** a service rather than redesigning the boundary.
| Capability | Business value | Why it needs AI |
|---|---|---|
| **Complaint parsing (LLM)** | Free-text symptoms → structured symptoms, duration, urgency, suggested specialty. With thousands of doctors, correct routing *is* the product | People describe problems in prose, not dropdowns |
| **Pre-consultation summary (LLM)** | Condenses a patient's history into a brief the doctor reads in 20 seconds before joining | Summarizing unstructured clinical notes |
| **Diagnosis → ICD-10 (Embeddings)** | Doctor writes "heart attack" → retrieves `I21.9 Acute myocardial infarction`; correct coding is required for records, insurance, and reporting | ~70,000 codes: too many for a dropdown, no keyword overlap with natural phrasing, too many classes for a prompt — and retrieval constrains the model to real codes instead of invented ones |
| **Help assistant (RAG)** | Answers "what do I need before my consultation?", "what is the cancellation policy?" from published help articles, with citations, and escalates to an admin when nothing relevant is found | Grounded, verifiable answers from a specific corpus |
| **Booking agent (Tool calling)** | "I need a skin doctor who speaks Arabic, this week, evenings, under 500" → agent calls `searchDoctors`, `getAvailableSlots`, `bookConsultation`, `rescheduleConsultation`, `requestInfo`, `escalateUrgent` | Unstructured input, multi-step reasoning, branching outcomes, real state changes — not reducible to a form or a query |

**Scope boundary:** AI handles discovery, scheduling, retrieval, summarization, and coding assistance. It never diagnoses, never prescribes, and never decides treatment. Red-flag symptoms escalate to a human immediately. Every AI-produced clinical artifact is a **draft the doctor confirms.**

## 13. Out of scope for MVP
Payments, payouts, and refunds · insurance claims · prescriptions and e-pharmacy · lab orders and results · the video infrastructure itself (a third-party room provider is assumed) · chat between consultations · ratings and reviews · SMS and WhatsApp channels · group practices and clinic accounts · mobile apps · waiting lists for fully booked doctors.

## 14. Appendix — API surface
**Identity Service**
```
POST   /auth/register              POST   /auth/login
POST   /auth/refresh               POST   /auth/logout
POST   /auth/verify-email          POST   /auth/resend-verification
POST   /auth/forgot-password       POST   /auth/reset-password
POST   /auth/change-password
GET    /auth/me                    PATCH  /auth/me
GET    /users                      GET    /users/:id
PATCH  /users/:id/status           GET    /users/:id/sessions
DELETE /users/:id/sessions
GET    /internal/users?ids=        PATCH  /internal/users/:id/status
```
**Care Service**
```
GET    /specialties                POST   /specialties
PATCH  /specialties/:id
POST   /doctors/apply              GET    /doctors/me
PATCH  /doctors/me                 POST   /doctors/me/documents
GET    /doctors/me/application
GET    /doctors                    GET    /doctors/:id
GET    /doctors/:id/slots
GET    /doctors/me/working-hours   PUT    /doctors/me/working-hours
GET    /doctors/me/exceptions      POST   /doctors/me/exceptions
DELETE /doctors/me/exceptions/:id
GET    /doctors/me/consultation-types
POST   /doctors/me/consultation-types
PATCH  /doctors/me/consultation-types/:id
GET    /admin/applications         GET    /admin/applications/:id
PATCH  /admin/applications/:id/approve
PATCH  /admin/applications/:id/reject
PATCH  /admin/doctors/:id/suspend
GET    /patients/me                PATCH  /patients/me
GET    /patients/:id               GET    /patients/:id/records
POST   /consultations              GET    /consultations
GET    /consultations/:id          PATCH  /consultations/:id/reschedule
PATCH  /consultations/:id/cancel   PATCH  /consultations/:id/join
PATCH  /consultations/:id/start    PATCH  /consultations/:id/complete
PATCH  /consultations/:id/no-show
GET    /consultations/waiting-room GET    /consultations/calendar
POST   /consultations/:id/record   GET    /records/:id
PATCH  /records/:id                POST   /records/:id/attachments
DELETE /records/:id/attachments/:aid
GET    /help-articles              GET    /help-articles/:id
POST   /help-articles              PATCH  /help-articles/:id
DELETE /help-articles/:id
GET    /audit-logs
GET    /internal/doctors/:userId/summary
```
