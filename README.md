# Vcare — Virtual Care Platform

The **main repository** for the Vcare platform: the aggregated, cross-service documentation hub. **No
application code** — this repo answers "how does the whole system fit together?" so a human (or an AI
agent) doesn't have to clone every service.

Vcare connects patients to **independent doctors for online consultations**: patients search by
specialty, language, price, or availability, book a slot, and meet by video; doctors set their own hours
and pricing and keep a structured record of every consultation.

## Services

| Service | Repository | Owns | Card | Contract |
|---|---|---|---|---|
| identity-service | [OmarRedaX/vcare-identity-api](https://github.com/OmarRedaX/vcare-identity-api) | accounts, authentication, tokens, sessions, account status, service tokens | [card](./catalog/identity-service.card.md) | [openapi](./contracts/identity-service.openapi.yaml) |
| care-service | [OmarRedaX/vcare-care-api](https://github.com/OmarRedaX/vcare-care-api) | doctors, verification, schedules, consultations, medical records, help center, audit | [card](./catalog/care-service.card.md) | [openapi](./contracts/care-service.openapi.yaml) |
| ai-retrieval-service | not created (Phase 2) | complaint parsing, summaries, ICD-10 lookup, help assistant, booking agent | — | — |

Full registry: [`catalog/service-catalog.md`](./catalog/service-catalog.md).

## Start here

| Doc | Read it when you need to… |
|---|---|
| [INDEX.md](./INDEX.md) | find where any answer lives — the router, **read first** |
| [product/prd.md](./product/prd.md) | know what the platform must do and why (source of intent) |
| [architecture/landscape.md](./architecture/landscape.md) | see both services, how they talk, and the three integration cases |
| [architecture/data-ownership.md](./architecture/data-ownership.md) | know which service is the single writer of which data |
| [adr/](./adr/) | read platform-level architecture decisions |
| [glossary.md](./glossary.md) | agree on what a term means |
| [CLAUDE.md](./CLAUDE.md) | understand the hub-and-spoke model and how agents retrieve docs |
| [TODO.md](./TODO.md) | see what is deliberately deferred |

## Working locally

Clone the repos as siblings. The service repos read this hub at `../vcare-hub`, so clone it under that
folder name:

```bash
mkdir vcare && cd vcare
git clone https://github.com/OmarRedaX/Vcare.git vcare-hub
git clone https://github.com/OmarRedaX/vcare-identity-api.git
git clone https://github.com/OmarRedaX/vcare-care-api.git
```

Docs live in each service repo (source of truth); this hub's cards and contracts are populated by
`scripts/sync-from-spoke.sh` and are never hand-edited:

```bash
cd vcare-hub
scripts/sync-from-spoke.sh identity-service ../vcare-identity-api
scripts/sync-from-spoke.sh care-service ../vcare-care-api
scripts/check-freshness.sh
```

Running the sync from spoke CI and a docs-lint workflow are deferred — see [`TODO.md`](./TODO.md).
