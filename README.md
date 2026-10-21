# n8n Workflows

Source of truth for our n8n automations. Every production workflow lives here as JSON, is reviewed via pull request, and is deployed to n8n from `main`.

## Structure

```
workflows/
  jira/        Jira ticket routing, SLA alerts, sync jobs
  airtable/    Airtable data pipelines and syncs
  ai/          AI API workflows (classification, summarisation, enrichment)
  wordpress/   WordPress publishing / content automations
  shared/      Sub-workflows reused by others (error handler, notifications)
docs/          Conventions, runbooks
scripts/       Export / import against the n8n API
```

## Quick start

```bash
cp .env.example .env          # add N8N_URL and N8N_API_KEY
./scripts/export.sh           # pull all workflows from n8n into workflows/
./scripts/import.sh workflows/jira/my-flow.json   # push one workflow to n8n
```

Requires `curl` and `jq`. Create the API key in n8n under **Settings → n8n API**.

## Workflow lifecycle

1. Build or edit in n8n (dev instance if you have one).
2. `./scripts/export.sh` → move the file into the right `workflows/<area>/` folder.
3. Branch, commit, open a PR. CI validates JSON and scans for secrets.
4. Merge to `main` → `./scripts/import.sh` to deploy (or automate via CI later).

See [docs/CONVENTIONS.md](docs/CONVENTIONS.md) for naming, tagging and error-handling standards.

## Rules

- **Never commit credentials.** Exports contain credential *references* (ID + name) only — keep it that way. Secrets live in n8n's credential store.
- One workflow per file, filename = slug of the workflow name.
- Every production workflow has an error workflow set (`shared/error-handler`).
