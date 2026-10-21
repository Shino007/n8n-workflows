# PromoMag v23 — deploy and cut-over

v23 (`workflows/promomag/promomag-generate-article-telegram-schedule-v23.json`) is a **new** workflow. v22 stays live until v23 has passed the tests below.

## 1–2. Deploy (done 21 Oct 2026 through the n8n MCP connector)

- `[SHARED] Error handler` was created and published as `QjNpLyKeMF4dFaQr`. It only runs when another workflow fails.
- v23 was created **inactive** as `1LoD338PhT6pNglJ`, with its error workflow set to the handler.
- It uses the existing credentials: Telegram account, n8n PromoMag and OpenAi account.
- The Pixabay key stays typed into *Fetch Pixabay API*, the same as in v22. In git it's `REDACTED_API_KEY`, so `import.sh` won't push this file. Change v23 through the connector or the n8n UI, then re-export. To make `import.sh` usable again, first move the key into a Query Auth credential (Name: `key`).

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
