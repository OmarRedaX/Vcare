#!/usr/bin/env bash
# Drift prevention: flag docs whose `last_verified` frontmatter is older than MAX_AGE_DAYS,
# and docs missing `last_verified` entirely. Exits non-zero if anything is stale or unstamped.
# Works on Linux, macOS, and Git Bash for Windows.
#
# Usage: scripts/check-freshness.sh [max_age_days]   (default 90)
set -euo pipefail

MAX_AGE_DAYS="${1:-90}"
HUB="$(cd "$(dirname "$0")/.." && pwd)"
now=$(date +%s)
stale=0
missing=0

while IFS= read -r -d '' f; do
  lv=$(grep -m1 -E '^last_verified:' "$f" | sed -E 's/last_verified:[[:space:]]*//; s/["'\'' \r]//g' || true)
  if [[ -z "$lv" ]]; then
    echo "MISSING last_verified: ${f#$HUB/}"
    missing=$((missing+1))
    continue
  fi
  # macOS/BSD date first, GNU date fallback (Linux, Git Bash)
  ts=$(date -j -f "%Y-%m-%d" "$lv" +%s 2>/dev/null || date -d "$lv" +%s 2>/dev/null || echo 0)
  age=$(( (now - ts) / 86400 ))
  if (( age > MAX_AGE_DAYS )); then
    echo "STALE (${age}d > ${MAX_AGE_DAYS}d): ${f#$HUB/}"
    stale=$((stale+1))
  fi
# README.md / CLAUDE.md / TODO.md are meta (no frontmatter by design) — skip them.
done < <(find "$HUB" -name '*.md' -not -path '*/.git/*' \
              -not -name 'README.md' -not -name 'CLAUDE.md' -not -name 'TODO.md' -print0)

echo "----"
echo "stale=$stale missing=$missing (max_age=${MAX_AGE_DAYS}d)"
(( stale == 0 && missing == 0 )) || { echo "FAIL: freshness check"; exit 1; }
echo "OK: all docs fresh and stamped"
