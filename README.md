# n8n Workflows

Source of truth for our n8n automations. Every production workflow lives here as JSON, is reviewed via pull request, and is deployed to n8n from `main`.

## Structure

```
workflows/
  promomag/      PromoMag article generation, topic research, featured images
  promoboost/    PromoBoost release analytics
  sla-manager/   SLA Contract Manager (extraction pipeline, manual entry, alert digest)
  swbw/          SWBW sign-up notifications and WhatsApp bot
  augmented/     Augmented anonymised meeting minutes
  mastery/       Mastery WordPress content agent
  shared/        Cross-project utilities (backup, error handler)
  <project>/archive/   Superseded versions kept for reference — not deployed
docs/            Conventions, runbooks
scripts/         Export / import against the n8n API (clean.py normalises + redacts)
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
- `scripts/clean.py` redacts hard-coded keys to `REDACTED_*` on export. A file containing a placeholder means that workflow still has a secret pasted into a node — move it to a credential. `import.sh` refuses to push such files.
- One workflow per file, filename = slug of the workflow name.
- Every production workflow has an error workflow set (`shared/error-handler`).
