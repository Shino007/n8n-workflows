# Workflow Conventions

## Naming

`[AREA] Verb Object (trigger)` — e.g. `[JIRA] Route new tickets (webhook)`, `[AIRTABLE] Sync clients nightly (cron)`.

Filename is the slugified name: `jira-route-new-tickets-webhook.json`.

## Tags (set in n8n)

| Tag | Meaning |
|---|---|
| `prod` / `dev` | Environment status |
| `owner:<name>` | Accountable person |
| `area:<jira\|airtable\|ai\|wordpress>` | Matches folder |
| `critical` | Pages someone on failure |

## Build standards

- **Error handling:** set *Settings → Error workflow* to `[SHARED] Error handler`. Critical flows alert to Slack/Teams.
- **Idempotency:** any workflow that writes (Jira, Airtable, WP) must be safe to re-run — check-before-create or upsert.
- **Secrets:** use n8n credentials only. No API keys in Code nodes, HTTP headers or expressions.
- **Sticky note** at the top of each workflow: purpose, owner, trigger, downstream systems.
- **AI nodes:** pin the model version, cap max tokens, log inputs/outputs for audit where data allows.
- **No pinned data** in committed exports (the export script strips it).

## PR checklist

- [ ] Correct folder and filename
- [ ] Error workflow set
- [ ] Sticky note filled in
- [ ] Tested on dev / with sample data
- [ ] No secrets or customer data in JSON
