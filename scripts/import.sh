#!/usr/bin/env bash
# Push workflow JSON files to n8n. Updates by ID if it exists, otherwise creates.
# Usage: ./scripts/import.sh workflows/jira/*.json
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .env ] && set -a && . ./.env && set +a
: "${N8N_URL:?Set N8N_URL in .env}" "${N8N_API_KEY:?Set N8N_API_KEY in .env}"
[ $# -gt 0 ] || { echo "Usage: $0 <workflow.json>..."; exit 1; }

api() { curl -fsS -H "X-N8N-API-KEY: $N8N_API_KEY" -H "Content-Type: application/json" "$@"; }

for f in "$@"; do
  # Pushing a redacted file would overwrite the live secret in n8n with the placeholder
  if grep -q 'REDACTED_' "$f"; then
    echo "skipped  $f — contains REDACTED_ placeholders; move the secret into an n8n credential first" >&2
    continue
  fi
  id=$(jq -r '.id // empty' "$f")
  # Public API only accepts these fields on create/update
  body=$(jq '{name, nodes, connections, settings: (.settings // {}), staticData}' "$f")
  if [ -n "$id" ] && api "$N8N_URL/api/v1/workflows/$id" >/dev/null 2>&1; then
    api -X PUT "$N8N_URL/api/v1/workflows/$id" -d "$body" >/dev/null
    echo "updated  $f ($id)"
  else
    new_id=$(api -X POST "$N8N_URL/api/v1/workflows" -d "$body" | jq -r '.id')
    echo "created  $f ($new_id) — re-run export.sh to capture the new ID"
  fi
done
