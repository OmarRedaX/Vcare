#!/usr/bin/env bash
# Sync the cross-cutting doc subset from a spoke repo into this hub.
# Intended to run from the SPOKE's CI on merge to main (deferred — see TODO.md); run manually for now.
#
# Usage: scripts/sync-from-spoke.sh <service-name> <path-to-spoke-repo>
# Examples:
#   scripts/sync-from-spoke.sh identity-service ../vcare-identity-api
#   scripts/sync-from-spoke.sh care-service ../vcare-care-api
#
# Copies:
#   <spoke>/docs/service-card.md   -> catalog/<service>.card.md          (SYNCED header + links rewritten)
#   <spoke>/contracts/openapi.yaml -> contracts/<service>.openapi.yaml  (verbatim)
# Event contracts (AsyncAPI) are future: MVP is HTTP-only, so nothing else is copied.
set -euo pipefail

SERVICE="${1:?service name required (e.g. identity-service)}"
SPOKE="${2:?path to spoke repo required (e.g. ../vcare-identity-api)}"
HUB="$(cd "$(dirname "$0")/.." && pwd)"
TODAY="$(date +%Y-%m-%d)"

card_src="$SPOKE/docs/service-card.md"
openapi_src="$SPOKE/contracts/openapi.yaml"

if [[ ! -d "$SPOKE" ]]; then
  echo "ERROR: spoke repo not found at '$SPOKE'" >&2
  exit 1
fi
if [[ ! -f "$card_src" ]]; then
  echo "ERROR: '$SPOKE' has no docs/service-card.md — create it in the spoke before syncing" >&2
  exit 1
fi
if [[ ! -f "$openapi_src" ]]; then
  echo "ERROR: '$SPOKE' has no contracts/openapi.yaml — create it in the spoke before syncing" >&2
  exit 1
fi

mkdir -p "$HUB/catalog" "$HUB/contracts"

echo "Syncing '$SERVICE' from $SPOKE → $HUB"

# 1. Service card → catalog/<service>.card.md
#    Relative links in the card are valid in the SPOKE but dead in the hub, so rewrite them to
#    resolve against the spoke repo on disk. From hub/catalog/ the spoke is one level further up
#    than $SPOKE (which is relative to the hub root): "../$SPOKE".
card_dst="$HUB/catalog/$SERVICE.card.md"
spokerel="../$SPOKE"                       # path to spoke as seen from hub/catalog/
{
  echo "<!-- SYNCED FILE — do not edit here. Source: $SERVICE/docs/service-card.md. synced_at: $TODAY -->"
  # ](../X) -> ](<spoke>/X)   (repo-root-relative);  ](./X) -> ](<spoke>/docs/X)  (card is in docs/)
  sed -E "s#\]\(\.\./#](${spokerel}/#g; s#\]\(\./#](${spokerel}/docs/#g" "$card_src"
} > "$card_dst"
echo "  ✓ card → catalog/$SERVICE.card.md (links rewritten to spoke)"

# 2. Contract → contracts/<service>.openapi.yaml
cp "$openapi_src" "$HUB/contracts/$SERVICE.openapi.yaml"
echo "  ✓ openapi → contracts/$SERVICE.openapi.yaml"

echo "Done. Review the diff, run scripts/check-freshness.sh, and commit on the hub."
