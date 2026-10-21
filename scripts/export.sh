#!/usr/bin/env bash
# Export all workflows from n8n into workflows/_inbox/ (move into the right area folder before committing).
# Existing files anywhere under workflows/ with the same name are updated in place.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .env ] && set -a && . ./.env && set +a
: "${N8N_URL:?Set N8N_URL in .env}" "${N8N_API_KEY:?Set N8N_API_KEY in .env}"

slugify() { echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g'; }

mkdir -p workflows/_inbox
cursor=""
count=0
while :; do
  url="$N8N_URL/api/v1/workflows?limit=100${cursor:+&cursor=$cursor}"
  page=$(curl -fsS -H "X-N8N-API-KEY: $N8N_API_KEY" "$url")
  while read -r wf; do
    name=$(jq -r '.name' <<<"$wf")
    file="$(slugify "$name").json"
    existing=$(find workflows -name "$file" -not -path '*/_inbox/*' | head -1)
    target=${existing:-workflows/_inbox/$file}
    # Keep only stable fields; drop pinned test data and volatile timestamps
    jq 'del(.pinData, .createdAt, .updatedAt, .shared, .versionId, .meta.instanceId)' <<<"$wf" > "$target"
    echo "exported  $target"
    count=$((count + 1))
  done < <(jq -c '.data[]' <<<"$page")
  cursor=$(jq -r '.nextCursor // empty' <<<"$page")
  [ -z "$cursor" ] && break
done
echo "Done: $count workflows."
