# PromoMag v23 — deploy and cut-over

v23 (`workflows/promomag/promomag-generate-article-telegram-schedule-v23.json`) is a **new** workflow. v22 stays live until v23 has passed the tests below.

## 1. Before merge (n8n UI, once)

1. **Pixabay credential.** If your Pixabay account lets you regenerate the API key, do that first, because the old one sat in plain text in several nodes. Then go to **Credentials → Add credential → Query Auth**:
   - Credential name: `Pixabay API`
   - Name: `key`
   - Value: the Pixabay API key
2. Note the credential ID: it's the last part of the credential's URL.

## 2. After merge (your machine)

```bash
git checkout main && git pull
./scripts/import.sh workflows/shared/shared-error-handler.json   # prints: created … (<ERROR_WF_ID>)

PIXABAY_ID=<credential id from step 1>
ERROR_WF_ID=<id printed above>
sed -i "s/__SET_ME_PIXABAY_CREDENTIAL_ID__/$PIXABAY_ID/g; s/__SET_ME_ERROR_WORKFLOW_ID__/$ERROR_WF_ID/g" \
  workflows/promomag/promomag-featured-image-swap.json \
  workflows/promomag/promomag-generate-article-telegram-schedule-v23.json

./scripts/import.sh workflows/promomag/promomag-featured-image-swap.json            # updates the live sub-workflow (v22-compatible)
./scripts/import.sh workflows/promomag/promomag-generate-article-telegram-schedule-v23.json   # creates v23, inactive

./scripts/export.sh   # v23 and the error handler land in workflows/_inbox/ with their new IDs
mv workflows/_inbox/promomag-generate-article-telegram-schedule-v23.json workflows/promomag/
mv workflows/_inbox/shared-error-handler.json workflows/shared/
# commit the filled-in IDs on a branch and open a PR so the repo matches n8n
```

`import.sh` refuses any file that still contains `__SET_ME_` or `REDACTED_`.

## 3. Test the scheduled path (v22 still live)

1. Open v23 in n8n, select **Schedule Trigger**, then **Execute workflow**.
2. Expect a Telegram message: *Scheduled draft ready*. It shows the title, the excerpt, the **Coverage** line, and whether an image is attached.
3. Tap **Let me tailor it**. You should get *Draft kept for editing* and nothing is published. (Tap **Publish now** only if you're happy for the article to go live.)
4. To test the drop path, run it again and ignore the message. After 6 hours you should get *Scheduled draft dropped*.
5. n8n doesn't call error workflows for manual runs. To check the alert, open **[SHARED] Error handler** and click **Execute workflow**: the Error Trigger supplies sample data, and you should get a 🚨 message in Telegram.

## 4. Cut over Telegram

Telegram allows only **one webhook per bot**. Deactivating a workflow deletes the bot's webhook, so the order matters:

1. **Deactivate v22.**
2. **Activate v23.**
3. Check in Telegram: `/status` → `technology` → pick `3` (check the outline is for topic 3) → `3` (neutral) → `post to WordPress` (draft) → `social` → `image city skyline`.

**Rollback:** deactivate v23, then activate v22.

## 5. After a week of clean runs

- Move the v22 file to `workflows/promomag/archive/` and archive it in n8n, along with the three v21 copies.
- Update the `dev` tag to `prod` on v23.
