# vcare-hub — Documentation Hub

The aggregated, cross-service documentation hub for the vcare Virtual Care Platform. **No application
code** — this repo answers "how does the whole system fit together?" so an AI agent (or a human)
doesn't have to clone every service.

**Start at [`INDEX.md`](./INDEX.md).** How docs get here and how an agent should retrieve them is in
[`CLAUDE.md`](./CLAUDE.md). What the platform must do is in [`product/prd.md`](./product/prd.md).

Spokes aggregated here:
- `identity-service` → `../vcare-identity-api`
- `care-service` → `../vcare-care-api`

Docs live in each spoke (source of truth); this hub is populated by `scripts/sync-from-spoke.sh`:

```bash
scripts/sync-from-spoke.sh identity-service ../vcare-identity-api
scripts/sync-from-spoke.sh care-service ../vcare-care-api
scripts/check-freshness.sh
```

Running the sync from spoke CI and a docs-lint workflow are deferred — see [`TODO.md`](./TODO.md).
