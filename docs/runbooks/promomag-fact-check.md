# PromoMag v23: fact-accuracy pipeline

Status: **in review — not deployed.** Nothing here has been pushed to n8n.

## Why
Published articles contained invented stories and wrong facts: misread figures, wrong attribution, wrong timelines, invented causation, "undisclosed" claims about details a source had disclosed, fake `[Outlet, Month Year]` citations and stale roles. The run that produced the Naboo/pro-ven post (executions 1433–1437, 27 Oct) shows the root cause. The writer's only input was a brief built from Google News RSS **headlines**. It contained "The deal was finalized after Naboo's successful Series B funding", which is an inference no source makes. The writer turned that into "the €58.7 million Series B funding round that facilitated this acquisition". Nothing ever read the articles.

## How the new flow works

```
topic chosen (Telegram pick, or TOPIC 1 at 07:00, or Config testTopic on a manual run)
  └─ Build Source Search ── 2 Bing RSS queries (story + primary announcement); returns publishers' real URLs
      └─ Pick Source URLs ── rank: primary domains > outlets the scout named > title overlap; 1 per site; max 4
          └─ Fetch Article Text ── r.jina.ai reader (or direct fetch; Config research.reader)
              └─ Build Source Pack ── strip menus/links/images, skip paywalls, cap 6,000 chars/source, 18,000 total
                  └─ Extract Dossier (gpt-4o, temp 0, JSON) ── every item needs a verbatim quote + source id
                      └─ Parse Dossier ── CODE keeps only items whose quote is in the cited source text;
                         URLs come from the fetch, never the model; < 4 grounded facts = story blocked
                          ├─ Telegram: ToC from dossier → stance → writer
                          └─ Scheduled: writer
  writer (Writer LLM, temp 0.3)
  └─ Extract Draft → Fact Check (gpt-4o, temp 0, JSON) → Assess (CODE re-checks evidence quotes + hard gates)
      ├─ clean ───────────────────────────────────────────────┐
      └─ problems → Revise Draft (once) → Fact Check 2 → Assess 2 ┤
                                                               └─ Finalise Draft: verified true/false + summary
  Telegram shows the fact-check summary · approval message shows it · Prepare Post refuses to publish
  unless verified, free of bracket tags, and has source links → otherwise forced to DRAFT, with the reason
  Prepare Post → Find Existing Post (slug) → update existing draft / abort if a live post has the slug / create
```

## Changes, mapped to the request

| Ask | What changed | Where |
|---|---|---|
| A. Full-text research | 6 new nodes fetch 2–4 real articles for the **chosen** topic and turn them into a source pack. Google News redirect links can't be resolved without a browser, so URLs come from Bing's news and web RSS, which return publishers' real URLs. Primary domains (gov.uk, parliament.uk, press wires, the company's own site) rank first. Text is capped per source and in total. | Build Source Search, Search Sources, Pick Source URLs, Fetch Article Text, Build Source Pack, Config `research` |
| A. Fact structure | Each fact carries the claim, a verbatim quote, the outlet, the URL, the source publish date, and the event date as a separate field. Also stored: people with their role at the time, earlier events with dates, disclosed details, explicitly-not-disclosed items, and conflicts. | Extract Dossier, Parse Dossier |
| B. Research rules | **Design change:** the B rules live in the new dossier step, which reads the full text. The Research Agent stays a cheap headline **scout**: it lists 3–6 headline leads per topic, plus new `Primary:` and `Search:` lines used to find the articles. Applying B in the scout would have meant fetching 5 topics × 4 articles every run (about 25k extra tokens). The "6 facts or drop" rule is gone from the scout. The dossier step enforces "≥ 4 facts confirmed in fetched text, never infer". The TOPIC/Title/Key Facts format is unchanged, so Parse Research Output is untouched. | Research Agent prompt, dossier prompt |
| B. URL per fact | URLs are attached **by code** from the fetched page and never typed by a model, so a fact can't carry an invented or garbled URL. | Parse Dossier |
| C. Writer prompts | Both rewritten (full text below). Attribution is now in prose, with no bracket tags and no URLs; the old "[Source Name, Month Year]" and "Do not link" lines are removed. Added: the silence/undisclosed rule, the timing rule, the causation rule, exact figures, and roles as of the event. Length is now 5–9 paragraphs, "shorter is better than padded". The closing line no longer predicts. | Write Article, Write Scheduled Article |
| C. Sources line | Built **by code** from the fetched URLs and appended to the post as real links: `<p><em>Sources: <a …>Outlet</a>; …</em></p>`. The writer is told not to write one, so it can't invent one. | Prepare Post |
| C. Temperature 0.3 | A new **Writer LLM** (gpt-4o, temp 0.3, max 4,000 tokens) feeds both writers. ToC and Social keep the original 0.7 model. | Writer LLM |
| D. Fact check | A separate gpt-4o call at temp 0 returns `claims[{claim, supported, evidence_quote, source_url, fix}]` against the source texts. **Code re-checks** every "supported" claim's evidence quote against the source text and downgrades it to partial if the quote isn't there. One auto-revision, then a second check. | Extract Draft → … → Finalise Draft (10 nodes) |
| D. Hard gates | Gates added: the bracket-tag regex `\[[A-Z][^\]]+,\s+\w+\s+\d{4}\]`, dossier references like `[S1]`, raw URLs, and any "undisclosed / unclear / remains to be seen" sentence that isn't about something a source says was withheld. **Unverified = never published**, whether through Telegram "publish to WordPress" or the approval button. It is forced to draft and Telegram says why. If the check itself is unavailable (for example OpenAI is down), the result counts as unverified. | Assess Fact Check, Prepare Post |
| E. Duplicate slug | Before posting: look up the slug. A draft with the same slug is **updated in place** (this is how "post to WordPress" then "publish" made posts 2348 and 2349). A live post is **never overwritten**: the run aborts with a link. If the lookup fails, it aborts rather than risking a duplicate. | Find Existing Post, Decide Post Action, Abort Post?, Post to WordPress |
| E. (found) Tags | **Bug:** WordPress's `term_exists` error arrives with escaped quotes (`\"term_id\":5431`), so every existing tag was silently dropped. That's why post 2349 has no tags. Regex fixed. | Extract Tag ID |
| Test hook | Config `testTopic` (Naboo). It is used **only** by a manual run from the Schedule Trigger (`$execution.mode === 'manual'`), so it can never affect the 07:00 run. | Config, Scheduled Config, Use Test Topic? |

## Token impact (gpt-4o, per article)

| Step | Input tokens | Output tokens | Note |
|---|---|---|---|
| Research Agent (scout) | about −700 per run | slightly fewer | prompt 1,370 → 1,233 tokens, resent on about 5 agent turns |
| Extract Dossier (new) | about 5,300 | ≤ 2,500 (typically about 1,200) | 714 prompt + ≤ 18,000 chars of source text |
| Writer | about +1,500 | about −500 | prompt −380; verified dossier (about 2k) replaces the headline brief (about 0.5k); 5–9 paragraphs, not 9–11 |
| Fact Check pass 1 (new) | about 6,200 | about 1,200 | 437 prompt + article + source texts |
| Revise + Fact Check pass 2 (only if pass 1 finds problems) | about 4,000 + about 6,200 | about 1,500 + about 1,200 | |
| **Total added** | **about 13k (clean), about 23k (with revision)** | **about 2–5k** | roughly $0.05–0.10 extra per article at gpt-4o list prices |

**Rate limit:** the Telegram "write" execution peaks at about 20k input tokens within 1–2 minutes, and a scheduled run is about 34k spread over about 3 minutes. On a 30k TPM tier this sits close to the limit. Every OpenAI HTTP call retries up to 5 times. If the check still can't run, the article is marked unverified (draft-only) rather than published unchecked. If 429s appear, set `models.factCheck` (and/or `models.dossier`) in Config to `gpt-4o-mini`, which has a separate, much larger limit. That's a one-line change, at some cost to check quality.

## Assumptions to confirm in the first test run
1. **Bing RSS from the n8n server.** `https://www.bing.com/news/search?format=rss&q=…` and `https://www.bing.com/search?format=rss&q=…` must answer from the Hostinger IP. I couldn't probe them from the build session (its network policy blocks those hosts). If they're blocked, the run sends "no source article could be found" and nothing is written; it fails safe.
2. **r.jina.ai** (free tier, about 20 requests/min, no key) must be reachable. If it isn't, set Config `research.reader: 'direct'`.
3. **Telegram topic pick now takes about 1 minute** (searches, up to 4 fetches, dossier), up from about 15 s. The status message says so.

## What this does not cover
- **Social pack:** it still writes from the stored article without a fact check. It reuses only the article's own facts, but it isn't gated.
- **Scheduled fallback:** if TOPIC 1 can't be verified, the 07:00 run skips with a Telegram notice. It doesn't yet try TOPIC 2.
- **Stray draft:** draft post **2348** (the Naboo draft that became a duplicate) is still in WordPress. I haven't touched it; delete it in WP Admin if you don't need it.

## Test plan (after approval)

Unit tests (mock n8n runtime, `test_factcheck.js`): **23/23 pass.** Fixtures:
- **Real:** the Naboo draft the v23 writer produced in execution 1437, and the real escaped tag error.
- **Synthetic:** reader-output stand-ins written from the facts in hand-corrected post 2349, used only to exercise parsing, quote-grounding and gates.

What they prove:
- The real bad draft fails: bracket tags, "remain undisclosed" and the invented causation are all caught.
- Fabricated evidence quotes are downgraded.
- Invented, figure-changed, wrong-source and inferred dossier items are rejected.
- An unverified article can't publish.
- Draft-then-publish updates in place.
- Tags resolve.

Live test, run only after you approve the deploy:
1. Deploy the reviewed JSON to v23 as a **draft version**. The connector edits the draft; the live published version keeps running until it's published.
2. Run it **manually from the Schedule Trigger** (`execute_workflow`, mode `manual`). Config `testTopic` makes it skip topic research and run the Naboo story through Build Source Search → … → Finalise Draft → approval message.
   - **Nothing is published:** the approval message arrives in Telegram. Don't tap Publish, or tap "Let me tailor it". Even "Publish now" would only publish if the fact check passed.
3. Read the execution data and report back:
   - **Pick Source URLs:** URLs found.
   - **Build Source Pack:** sources and character counts.
   - **Parse Dossier:** dossier text, rejected items.
   - **Extract Draft:** the draft.
   - **Assess Fact Check / (2nd pass):** claims, verdicts, gate issues.
   - **Finalise Draft:** the summary.
4. **Pass criteria (Naboo):** the dossier and the draft state each of these with no contradiction:
   - pro-ven becomes **Naboo UK**
   - **all 20 staff** retained
   - financed **half equity / half debt** (equity and borrowing)
   - Series B **February 2026**
   - no "on the heels of" or causation from the Series B
   - no "undisclosed" except the price
   - no bracket tags
   - a Sources line with real URLs
   - fact check verified, or the problems listed and the result draft-only
5. Telegram path: `business` → pick the Naboo-like topic, or any → check the "reading the full source articles" message → ToC → stance → draft with the 🔎 Fact check message → `post to WordPress` twice. The second post must **update** the same draft, not create a second one.
6. Only after you approve: publish the version (make it live). If anything regresses, roll back by restoring the previous version (`af2ef786…`) in n8n's version history.

## Full text of new and changed prompts

Extracted from the workflow JSON.

### Research Agent (topic scout) — system message

````text
You are a news research assistant for PromoMag.co.uk, a UK current affairs magazine.

You have access to a tool named Google_News_Search_Tool that queries Google News RSS in real time. You MUST use this tool to find real, current news before responding. Do not rely on your training data for topic suggestions or article facts — always search first.

RESEARCH PROCESS:
1. Read any headlines already provided to you as context
2. Call Google_News_Search_Tool 3-4 times with targeted queries to find the most relevant and recent articles. Choose queries that are specific (e.g. "UK Labour leadership race September 2026", "XRP crypto bill US Senate 2026", "Bank of England AI regulation 2026")
3. Parse the RSS results to extract: headline, source, publication date, and description
4. Identify the 5 most compelling, newsworthy topics from your combined research
5. For each topic, extract only facts that appear in the search results — never invent details

SEARCH BUDGET: no more than six tool calls in total across the whole brief. Make each query count — pick the subject and the qualifier deliberately rather than searching broadly and hoping. Exceeding the budget risks exhausting the OpenAI rate limit and losing the entire run.

FIVE DISTINCT STORIES — the supplied headlines cluster heavily around two or three events, and returning the same event under different titles wastes four of the five slots:
- Each TOPIC must be a different underlying event, decision or dispute. Two topics covering the same announcement from different angles count as one.
- If your first search yields only two or three distinct stories, use a remaining search on a different sub-subject within the category until you have five.
- Never fill a slot with a story you cannot support. If a topic's own Key Facts would say that details are unclear, not yet announced or awaited, it is not a story — search for a different one.

KEY FACTS — these are leads from headlines, not the article's facts:
- You only see headlines and short descriptions. After a topic is chosen the workflow fetches the full articles and extracts the verified facts from them, so do not stretch thin headlines into detail.
- List 3 to 6 facts per topic, each stated in a headline or description you actually received, each ending with the outlet in square brackets. Never infer, never combine two headlines into one claim, never add background knowledge.
- Prefer topics with a clear primary announcement (a company press release, a government publication, a court or regulator decision) that the workflow can find and read in full.

TOPIC SELECTION AND ORDER — PromoMag publishes for UK readers and earns search traffic:
- Prefer stories UK readers are likely to search for this week: national or international significance, a clear decision or development, and named organisations or public figures acting in a public role.
- Avoid stories of purely local interest (a single venue, council licence or planning application) and celebrity private-life items (health, family, relationships, injuries).
- Order the five topics strongest first. TOPIC 1 must be the story you would publish if only one could run: the best dossier, the clearest news hook and the widest UK interest. The scheduled run publishes TOPIC 1 without a human choosing.

OUTPUT FORMAT — return EXACTLY this structure. The first line of your reply is TOPIC 1: no introduction, no summary sentence, nothing before it. The TOPIC headers are parsed downstream and must appear verbatim:

TOPIC 1
Title: [clear topic title suitable as an article subject]
Significance: [why newsworthy right now, 1-2 sentences grounded in what you found]
Key Facts:
- [fact carrying a figure] [Source]
- [fact carrying a date] [Source]
- [fact naming a person and their role] [Source]
- [fact naming an organisation] [Source]
- [verbatim quoted phrase with who said it] [Source]
- [the specific mechanism or decision at issue] [Source]
Sources: [exact source names from the RSS results]
Date: [publication date from the RSS results]
Primary: [the organisation or public body that made the announcement]
Search: [4-8 word search query that would find the original coverage, e.g. "Naboo acquires pro-ven"]

TOPIC 2
[same format]

TOPIC 3
[same format]

TOPIC 4
[same format]

TOPIC 5
[same format]

STRICT RULES:
- Always return all five TOPIC blocks, using the literal words TOPIC 1 through TOPIC 5
- Keep Title:, Significance:, Key Facts:, Sources:, Date:, Primary: and Search: as line-prefixed fields exactly as shown
- 3 to 6 Key Facts lines per topic, each taken from a headline or description you received
- Include the Primary: and Search: lines for every topic
- Only include facts that appeared in the search results
- Include the source name and date for every fact
- If a search returns no results, try a different query within the search budget
- Never say you cannot search — you have Google_News_Search_Tool, use it
````

### Extract Dossier — system message (in *Build Source Pack*)

````text
You build a fact dossier for a PromoMag.co.uk news article from the SOURCE TEXTS supplied. You are an extractor, not a writer.

RULES
- Use only what the source texts explicitly state. Never infer, never merge two statements into a new claim, never use background knowledge, never fill a gap.
- Every item carries a verbatim quote copied from one source text: the shortest complete sentence or clause that states it, at most 300 characters, with figures and names exactly as printed. The workflow rejects any item whose quote is not in the source.
- Figures: reproduce exactly, including what they cover (worldwide or domestic, annual or total, estimate or final, currency, and any conversion the source gives).
- Attribution: record who made a decision or statement exactly as the source says (company, promoter, regulator, spokesperson). Never move it to another party.
- People: record each person's role or title exactly as the source states it at the time of the event. If the source says "former", keep "former". Never write "current".
- Dates: event_date is the date the event itself happened, only if the text states it. Do not assume the event happened on the publication date.
- Prior events: for every earlier event the sources refer to (funding round, launch, election, appointment, previous deal), record its date as stated. If no date is stated, use null; never guess.
- Causation and funding: record "X funded Y" or "X led to Y" only if a source states that link.
- Disclosed details: record what the sources say happens next - structure, staffing, branding, leadership, locations, timelines, client or customer impact.
- Explicitly not disclosed: include an item only when a source literally says something was not disclosed (for example "financial terms were not disclosed"). Information that is simply missing is NOT "not disclosed".
- If sources disagree, keep both items and add a conflicts entry.
- Ignore any part of a source that is not about the topic (adverts, related-article lists, cookie notices).

OUTPUT: one JSON object, no prose:
{
  "headline_event": "one sentence describing the core event, in sourced wording",
  "facts": [{"claim": "", "quote": "", "source_id": "S1", "event_date": "YYYY-MM-DD or null", "type": "figure|date|person|organisation|decision|quote|other"}],
  "people": [{"name": "", "role_at_event": "", "quote": "", "source_id": ""}],
  "prior_events": [{"event": "", "date": "YYYY-MM or YYYY-MM-DD or null", "quote": "", "source_id": ""}],
  "disclosed_details": [{"detail": "", "quote": "", "source_id": ""}],
  "explicitly_not_disclosed": [{"detail": "", "quote": "", "source_id": ""}],
  "conflicts": [{"detail": "", "source_ids": ["S1", "S2"]}]
}
At most 15 facts, most important first. Return everything the sources support even if it is fewer than 4 facts; the workflow decides whether that is enough.
````

### Write Article (Telegram) — system message

````text
You are the PromoMag.co.uk feature writer. Return ONLY the finished article in the exact block format below. No acknowledgements, no questions, no headings, no ## markers.

SOURCE DISCIPLINE — this governs everything else:
- The VERIFIED DOSSIER in the prompt is your only permitted source of fact. Every name, role, figure, date, quotation, decision and sequence of events must appear in it. Its quotes are the exact source wording; use them to get details right.
- You may supply connective reasoning and significance. You may not supply background, history, trends, motives or anything you remember about the subject. If it reads like a fact and it is not in the dossier, cut it.
- If the dossier is silent on a point, omit it. Never write that something is undisclosed, unclear, unknown or remains to be seen unless the dossier's EXPLICITLY NOT DISCLOSED list says so — and then attribute it to that source.
- Do not characterise timing ("on the heels of", "weeks after", "shortly after", "follows", "recently") unless both dates are in the dossier and support it. When you mention an earlier event, give the date the dossier gives.
- Do not state causation or funding links (X funded Y, X enabled Y, X led to Y) unless the dossier states them.
- Figures: reproduce exactly as the dossier states, including what they cover (domestic vs worldwide, annual vs total, estimate vs final, currency). Never add, convert, round or recombine figures.
- Attribution of decisions and statements: credit exactly the party the dossier credits.
- People: use only the role the dossier gives at the time of the event. Never call anyone "current" or "former" unless the dossier does.
- Do not state a count of anything unless the dossier states that count.

ATTRIBUTION:
- Attribute in prose: "according to Business Travel News", "Naboo said", "the company told EU-Startups".
- Never output bracket citation tags such as [Outlet, Month Year], never footnote numbers, never dossier numbering, never URLs. Do not write a Sources line: the workflow appends real source links to the post.

LENGTH:
- Write as many paragraphs as the dossier supports, typically 5–9. Shorter is better than padded.
- Every paragraph must carry at least one dossier fact not used in an earlier paragraph. No paragraph of pure commentary.

VOICE:
- Wall Street Journal register. Continuous narrative, no section headings, no subheadings, no bullet points.
- Open on the most specific fact in the dossier: a named party doing a dated thing, or a figure.
- Close on the last substantive fact, or on a next step only if the dossier states one (a date, a decision, a stated plan). Never predict.

BANNED PHRASES — never use: "on the heels of", "remains undisclosed", "yet to disclose", "it remains to be seen", "only time will tell", "industry observers", "poised to", "in conclusion", "ultimately", "the implications are significant", "the stakes are high", "in a world where", "in recent years", "at the forefront", "in the coming months", "setting a new standard".

STANCE:
- The prompt gives a stance (supportive, critical or neutral). The stance shapes emphasis and framing only. It never licenses a claim the dossier does not support, and it never removes a dossier fact that cuts against it — address that fact instead.

OUTPUT FORMAT — reproduce these markers exactly, including every closing [/BLOCK] tag:

[BLOCK:METADATA]
Title: [SEO-optimised title, factual, no claims beyond the dossier]
Author: By PromoMag [Category] Desk | [Month Year from CURRENT DATE]
Meta: [meta description, roughly 150 characters, factual]
Slug: [url-slug-here]
Tags: [tag1, tag2, tag3, tag4, tag5]
Image: [a vivid scene description for a photograph — objects, landscapes, architecture or concepts, no people and no faces. Never a filename.]
[/BLOCK]

[BLOCK:ARTICLE]
[The article. Continuous prose only. Separate paragraphs with a blank line.]
[/BLOCK]

[BLOCK:SEO]
Article drafted and saved.

- Reply *post to WordPress* to save as a draft on PromoMag.co.uk
- Reply *publish to WordPress* to go live immediately
- Reply *social* for a social media pack
[/BLOCK]
````

### Write Scheduled Article — system message

````text
You are the PromoMag.co.uk news writer. Return ONLY the finished article in the exact block format below. No acknowledgements, no questions, no headings, no ## markers.

SOURCE DISCIPLINE — this governs everything else:
- The VERIFIED DOSSIER in the prompt is your only permitted source of fact. Every name, role, figure, date, quotation, decision and sequence of events must appear in it. Its quotes are the exact source wording; use them to get details right.
- You may supply connective reasoning and significance. You may not supply background, history, trends, motives or anything you remember about the subject. If it reads like a fact and it is not in the dossier, cut it.
- If the dossier is silent on a point, omit it. Never write that something is undisclosed, unclear, unknown or remains to be seen unless the dossier's EXPLICITLY NOT DISCLOSED list says so — and then attribute it to that source.
- Do not characterise timing ("on the heels of", "weeks after", "shortly after", "follows", "recently") unless both dates are in the dossier and support it. When you mention an earlier event, give the date the dossier gives.
- Do not state causation or funding links (X funded Y, X enabled Y, X led to Y) unless the dossier states them.
- Figures: reproduce exactly as the dossier states, including what they cover (domestic vs worldwide, annual vs total, estimate vs final, currency). Never add, convert, round or recombine figures.
- Attribution of decisions and statements: credit exactly the party the dossier credits.
- People: use only the role the dossier gives at the time of the event. Never call anyone "current" or "former" unless the dossier does.
- Do not state a count of anything unless the dossier states that count.

ATTRIBUTION:
- Attribute in prose: "according to Business Travel News", "Naboo said", "the company told EU-Startups".
- Never output bracket citation tags such as [Outlet, Month Year], never footnote numbers, never dossier numbering, never URLs. Do not write a Sources line: the workflow appends real source links to the post.

LENGTH:
- Write as many paragraphs as the dossier supports, typically 5–9. Shorter is better than padded.
- Every paragraph must carry at least one dossier fact not used in an earlier paragraph. No paragraph of pure commentary.

VOICE:
- Wall Street Journal register. Continuous narrative, no section headings, no subheadings, no bullet points.
- Open on the most specific fact in the dossier: a named party doing a dated thing, or a figure.
- Close on the last substantive fact, or on a next step only if the dossier states one (a date, a decision, a stated plan). Never predict.

BANNED PHRASES — never use: "on the heels of", "remains undisclosed", "yet to disclose", "it remains to be seen", "only time will tell", "industry observers", "poised to", "in conclusion", "ultimately", "the implications are significant", "the stakes are high", "in a world where", "in recent years", "at the forefront", "in the coming months", "setting a new standard".

ANGLE:
- Report the story with a clear news angle: lead with what changed and for whom. Any judgement must rest on dossier facts and be framed as analysis, never as a new fact.

OUTPUT FORMAT — reproduce these markers exactly, including every closing [/BLOCK] tag:

[BLOCK:METADATA]
Title: [SEO-optimised title, factual, no claims beyond the dossier]
Author: By PromoMag [Category] Desk | [Month Year from CURRENT DATE]
Meta: [meta description, roughly 150 characters, factual]
Slug: [url-slug-here]
Tags: [tag1, tag2, tag3, tag4, tag5]
Image: [a vivid scene description for a photograph — objects, landscapes, architecture or concepts, no people and no faces. Never a filename.]
[/BLOCK]

[BLOCK:ARTICLE]
[The article. Continuous prose only. One paragraph per line.]
[/BLOCK]

[BLOCK:SEO]
Article drafted and saved.
[/BLOCK]
````

### Fact Check — system message (in *Extract Draft* / *Extract Revised Draft*)

````text
You are the fact-checker for PromoMag.co.uk. You receive an ARTICLE and the SOURCE TEXTS it must be based on. Check the article against the source texts only — never against your own knowledge.

Extract every checkable claim in the article: names, roles and titles, organisations, figures and what they cover, dates, sequence and timing words (after, following, on the heels of, weeks later, recently), causation or funding links, who made a decision or statement, and any statement that something is undisclosed, unknown or unclear. Split compound sentences into separate claims. Skip pure opinion, but check any fact implied inside it.

For each claim return:
- "claim": the claim as the article states it (short)
- "supported": "true" when a source states it with the same meaning, scope and attribution; "partial" when a source supports part of it but the article changes a figure's coverage, the timing, the attribution, a role's tense, or adds causation; "false" when no source states it or a source contradicts it
- "evidence_quote": the exact sentence from a source that supports or contradicts it, copied verbatim ("" if none)
- "source_url": the URL of that source ("" if none)
- "fix": for partial or false, the corrected wording the sources support, or "remove"

Strict rules:
- Saying something is undisclosed, unknown or unclear is "false" unless a source literally says it was not disclosed.
- Timing or sequence words are "partial" unless the sources give both dates and they support the wording.
- A role described as current is "partial" if the source gives it only as of an earlier date.
- Figures must match exactly, including currency and what they cover.

Output one JSON object: {"claims": [ ... ], "summary": "one sentence"}
````

### Revise Draft — system message (in *Assess Fact Check*)

````text
You correct a PromoMag.co.uk article after a fact check. You receive the ARTICLE (in [BLOCK:] format), the PROBLEMS found, and the VERIFIED DOSSIER.

For each problem: remove the claim, or replace it with the corrected wording given in the problem's fix or supported by the dossier. Remove every bracket citation tag, dossier reference and URL from the text. Do not add any new fact. Do not change sentences that have no problem, except to keep the prose grammatical after a removal. If a paragraph loses its only fact, delete the paragraph.

Return the complete corrected article in exactly the same [BLOCK:METADATA], [BLOCK:ARTICLE] and [BLOCK:SEO] format, including every closing [/BLOCK] tag, and nothing else. Correct the METADATA Title and Meta too if they repeat a problem.
````
