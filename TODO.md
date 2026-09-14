# Hub — Deferred (TODO)

Things intentionally **not** built yet. Captured here so they're a decision, not a gap.

## CI / automation (deferred — do later)
- [ ] **Docs-lint CI** — a GitHub Actions workflow that runs on every hub PR:
  - `scripts/check-freshness.sh` (frontmatter `last_verified` freshness) — already written, run manually for now.
  - a broken-internal-link check across hub docs (including links rewritten into synced cards).
  - **contract drift**: check out each spoke in CI and `diff` `contracts/<service>.openapi.yaml` here against the spoke's `contracts/openapi.yaml` (fail on drift). Today the sync just copies; there's no automated guard.
- [ ] **Sync trigger** — have each spoke's CI call `scripts/sync-from-spoke.sh` on merge to main and open a hub PR (today it's run manually).

## Events / AsyncAPI (once a message bus exists)
MVP is HTTP-only; there are no event contracts. When an ADR adopts a bus (RabbitMQ is the candidate
named by care-service), add `contracts/<service>.asyncapi.yaml` to the sync and an event-flow table to
`architecture/landscape.md`. Candidate events already named by the spokes:
- [ ] identity-service: `user.registered`, `user.status_changed`
- [ ] care-service: `consultation.booked`, `consultation.cancelled`, `doctor.suspended`

## Known architecture gaps
- [ ] **Identity-originated doctor status change** — an admin changing a doctor's status directly via
  Identity's `PATCH /api/users/:id/status` is not pushed to Care in the HTTP-only MVP. Close it via
  `/system-design` (options include a `user.status_changed` event, a Care-owned callback, or forbidding
  doctor status changes outside Care), then update `architecture/landscape.md` and add a hub ADR.
- [ ] **Doctor reinstatement** — `suspended → active` exists only as an Identity admin action; Care has no
  reinstatement endpoint and keeps `suspended_at`. Design the Care-side flow (and its Case-3-style
  failure policy) together with the gap above.
- [ ] **`doctors:read` consumer** — the scope and Care's `/internal/doctors/:userId/summary` exist, but no
  service client holds the scope in MVP. Provision one when admin tooling or the Phase-2 AI service needs it.

## Phase-2 AI & Retrieval service onboarding
- [ ] New row in `catalog/service-catalog.md` (currently "planned") and a spoke repo with `docs/service-card.md` + `contracts/openapi.yaml`, then run the sync.
- [ ] A service client in Identity (`service_clients`) with its own allowed scopes.
- [ ] Define the Care internal endpoints and scopes its tools need (`searchDoctors`, `getAvailableSlots`, `bookConsultation`, `rescheduleConsultation`) — provider contract lands first in care-service.
- [ ] Landscape node, data-ownership rows (vector store, AI drafts), glossary terms.

## Discoverability
- [ ] Semantic search / **docs-MCP** over the hub corpus. The `INDEX.md` router is the retrieval mechanism until volume forces it.

## Glossary / ownership upkeep
- [ ] Keep `glossary.md` and `architecture/data-ownership.md` rolled up as modules are built and services are added.
