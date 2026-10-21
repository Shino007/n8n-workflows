#!/usr/bin/env bash
# Export all workflows from n8n. Files already in the repo are updated in place (matched by
# workflow ID); new workflows land in workflows/_inbox/ to be moved into a project folder.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .env ] && set -a && . ./.env && set +a
: "${N8N_URL:?Set N8N_URL in .env}" "${N8N_API_KEY:?Set N8N_API_KEY in .env}"

slugify() { echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g'; }

# Map workflow ID -> existing file
declare -A existing
while IFS=$'\t' read -r id path; do existing[$id]=$path; done < <(
  find workflows -name '*.json' -not -path '*/_inbox/*' -exec jq -r '[.id, input_filename] | @tsv' {} \;
)

mkdir -p workflows/_inbox
cursor=""
count=0
while :; do
  page=$(curl -fsS -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_URL/api/v1/workflows?limit=100${cursor:+&cursor=$cursor}")
  while read -r wf; do
    id=$(jq -r '.id' <<<"$wf")
    target=${existing[$id]:-workflows/_inbox/$(slugify "$(jq -r '.name' <<<"$wf")").json}
    python3 scripts/clean.py <<<"$wf" > "$target"
    echo "exported  $target"
    count=$((count + 1))
  done < <(jq -c '.data[]' <<<"$page")
  cursor=$(jq -r '.nextCursor // empty' <<<"$page")
  [ -z "$cursor" ] && break
done
echo "Done: $count workflows."
grep -rl 'REDACTED_' workflows >/dev/null && echo "Note: some workflows contain hard-coded secrets (now REDACTED_*). Move them into n8n credentials."
exit 0
