# Gallery of the Day — Refactor Plan

> Bring Gallery of the Day in line with how FillariStatus and TuneTeller are built (`fillaristatus-plan.md`, `tuneteller-refactor-plan.md`): small focused files, config and text in one place, scripts that fail loudly and never silently, tests with mocked HTTP, security headers, and automatic keyless deploys.
>
> **For Claude Code:** read this whole file first. **Every change is checked with the user before it is committed, pushed or deployed.** Phase 0 and Phase 3 touch GitHub settings, OpenAI spend and cloud resources: each step needs approval. Never print secrets (see section 9).

*Written 2026-10-18; status table updated 2026-10-21. The plan was carried out between 2026-10-18 and 2026-10-21: the status table below says what happened, and sections 1 to 10 are the original plan, kept as written (they still say "not implemented" in places). Items marked (unverified) were not checked when written.*

---

## 0. Status at a glance

| # | What | Status |
|---|---|---|
| 0 | Daily workflow disabled by GitHub (`disabled_inactivity`); no new image since 2026-06-27 | **Fixed 2026-10-18/19**: re-enabled, keep-alive step (whether it holds is only proven over the coming weeks), minimal permissions, manual `backfill.yml`. All 114 days 2026-06-28 to 2026-10-19 backfilled and checked in Turso and R2 (2026-10-01 needed another event: the model chose Walt Disney World and the image API blocked "Mickey Mouse ears") |
| 1 | Footer: add FillariStatus | **Done** (app footer in `app/ui.R`, project page live; the app change goes live at the next deploy) |
| 2 | Models: replace `gpt-4o-mini` (retired 2027-01-14); review `gpt-image-1.5` | **Done 2026-10-19**: `gpt-5.6-luna` + `gpt-image-2.5-sunburst` high, in `R/config.R` and `R/openai.R`, 15 tests; verified by a real run in GitHub Actions (R 4.5, locked packages) for 2026-10-19. Open: the model still invents events on hard dates (see 4.6) |
| 2b | Accuracy: events grounded in Wikipedia's "On this day" list, no text in images, category rotation; 199 mismatched days regenerated (old ones archived in R2 `archive/2026-10-19/` and Turso `prompts_archive`) | **Done 2026-10-19.** Code `219b829`, `aa3b951`; 200 days regenerated (the 199 plus 2026-08-11, which the first audit's lenient judge let through); old ones archived (200 rows in `prompts_archive`). Re-audit: all 292 captions match a real event on their date. One R2 502 stopped 2026-07-13; `R/r2.R` now retries (`73e158f`) |
| 2c | App: FillariStatus footer link, generic disclaimer, youcanbeapirate theme with light/dark switch (dark default), reconnect fix (`--timeout 3600`, `--session-affinity`, `allowReconnect("force")`) | Committed; first deploy (revision `00010-2cg`) live with the footer link and disclaimer; theme and reconnect fix in the second deploy |
| 2d | Security step 1, GitHub hygiene (2026-10-19): secret scanning, push protection, Dependabot alerts and security updates, `main` protected (no force-push or deletion, enforced for admins), actions pinned to commit SHAs, `dependabot.yml`; read back identical to FillariStatus; 0 secret-scanning and 0 Dependabot alerts | **Done**; the SHA pins are proven only by the next workflow run |
| 2e | Security step 3 (2026-10-19): `app/www/security.R` + `run.R` (enforced CSP for the fonts host and the R2 image host, X-Frame-Options, nosniff, Referrer-Policy, Permissions-Policy, HSTS); `Dockerfile` on `rocker/r-ver:4.5.2` as non-root user `gallery` restoring only the app's packages; allowlist `.dockerignore`; 33 tests. Tested on the real image: headers present, uid 997, locked package versions, full app run in Chrome with a CSP violation recorder shows zero real violations (Shiny 1.12.1's own `setTimeout(undefined)` gives one harmless "eval" report) | **Deployed and verified 2026-10-19** (commit `7136c74`, revision `gallery-of-the-day-app-00012-mk9`, 100% of traffic): build 4 min, cold start about 3.8 s, all six headers on the live domain, logs clean (only 200/304), live browser run (images from R2, Gotham, date picker, arrow keys, lightbox, theme switch, reconnect) with no violations from a listener installed after load. Rollback: point traffic at `00011-vkh` |
| 3 | Phase 1: app and script code refactor | **Done 2026-10-20/21, deployed** (revision `00024-rrh`): shared R code and 290 tests; app files split (`global.R`, `www/variables.R`, `strings.R`, `lightbox.js`, `data.R`, `health.R`); error states for Turso down, an empty table, a date without a prompt and a missing R2 image; a stale-data note; an in-memory prompts cache (5 min fresh, old copy served up to 7 days, 30 s pause after a failure, warmed at start); the lightbox built with DOM calls (the old string-joined HTML could be injected through the alt text, proved in Chrome); one Turso client in `R/turso.R` shared by the scripts and the app (reads: 8 s timeout and one retry; writes: 30 s, never retried; the requests are byte for byte the old ones); `secret.R`, `R/deploy_app.R`, `R/backfill.R` and the migration scripts removed. **Not done:** `R/check_missing_days.R` (replaced by the `/health` staleness alert, row 5); `app/app_cache/` was root-owned; the owner removed it on 2026-10-22 |
| 4 | Phase 2: infrastructure | **Done 2026-10-19/20, partly:** runtime account `gallery-runtime`, `roles/editor` removed, `--max-instances 3`, keyless deploys (`gallery-deploy`, pool `gallery`; tested from `main`, refused from another branch). **Also done 2026-10-20/21:** `tests.yml` (runs on push and pull requests, 290 tests), Artifact Registry cleanup policy (keep the 5 newest, delete versions older than 14 days; the 10 February images are gone), a EUR 10 a month budget alert for this project. **Decided:** deploys stay manual (`workflow_dispatch`). **Also:** `testthat` 3.3.2 and its dependencies are pinned in `renv.lock` (2026-10-22), and `tests.yml` no longer installs it from CRAN |
| 5 | Monitoring (the plan's 4.4, in a different form) | **Done 2026-10-21:** `GET /health` (200 `ok` or 503 with `unavailable`, `empty`, `stale` (newest image more than 1 day old) or `degraded` (cached copy served because Turso fails)); a Cloud Monitoring uptime check every 5 minutes from 6 regions; an alert policy that emails the owner when it fails for 10 minutes (definition in `monitoring/health-alert-policy.json`). Tested end to end with a temporary always-failing check: both the alert and the recovery emails arrived. The production alert itself has not fired for real |
| 6 | Still open (2026-10-22) | **Done 2026-10-22:** the owner removed the root-owned `app/app_cache/`. **On or after 2026-11-02:** check the Artifact Registry cleanup (the 7 images from 2026-10-19 on pass 14 days; everything beyond the newest 5 should go). **First scheduled run after `7d0ff7b`** (about 08:58 UTC on 2026-10-22): confirm it restores the larger `renv.lock`. **Unproven:** the production uptime alert has never fired for real (only a temporary copy was tested); the keep-alive step against the 60-day disable only shows after a long quiet period. **Not built:** `R/check_missing_days.R` (the `/health` staleness alert replaces it) |
| 7 | Notes | **Local R is 4.6.1, the lockfile is for 4.5.2:** the locked `rlang 1.1.7` doesn't compile on 4.6.1, so `renv::restore()` fails locally; CI and Docker use R 4.5 and are fine. Verify lockfile changes in a `rocker/r-ver:4.5.2` container. **PHP2Shell (CVE-2026-109618/109619, 2026-10-21):** checked 2026-10-22, no effect: this app and the image have no PHP or Apache, and no sibling project in `~/VSCode` uses PHP |

Live: https://galleryoftheday.youcanbeapirate.com (HTTP 200, serving a new image every day since 2026-10-19; was frozen on 2026-06-27 until then). Cloud Run service `gallery-of-the-day-app`, project `gallery-of-the-day-app`, region `europe-north1`.

## 1. Why

- **The daily job has been off since June.** GitHub disables scheduled workflows after 60 days without repo activity. The last commit is 2026-04-27 and the last scheduled run 2026-06-27 (60 days later). The workflow's state is `disabled_inactivity`. Every run before that succeeded, so it was not a code or API failure. The job never commits (data goes to Turso and R2), so nothing keeps the repo "active". Nobody noticed because nothing reports a missing day.
- **Data gap:** Turso holds 178 prompts, 2026-01-01 to 2026-06-27. Days 2026-06-28 to 2026-10-18 (113 days) have no prompt and no image.
- **Deadline: `gpt-4o-mini` is retired on 2027-01-14** (OpenAI notice, as recorded in the TuneTeller plan). It is hard-coded in `create_prompt.R` and twice in `fetch_image.R` (sanitise, alternative event), and named in the UI disclaimer and README.
- **Structure is the old one:** no `global.R`, `variables.R`, `strings.R`, tests, security headers, CI gate or smoke test. `turso.R` exists twice (`R/` and `app/www/`). Deploys run as the default compute account (it probably still has `roles/editor`, unverified), on `rocker/shiny:4.4.3` with a 300 s timeout.
- **Latent bug:** `fetch_image.R` reads the *latest* prompt (`ORDER BY date DESC LIMIT 1`), not today's. If `create_prompt.R` skipped or failed, it would make today's image from an older prompt.

## 2. Decisions (to confirm with the user)

| Question | Proposed | Status |
|---|---|---|
| How to keep the schedule alive | Re-enable the workflow, plus a final step that re-enables it through the API on every run (no commits). Check after ~4 weeks that it holds. Alternatives: Cloud Scheduler (not subject to the rule, more setup); cron empty commits (clutters history) | **Open** |
| Failure alert | A failed run must be noticed: at minimum GitHub's failure email, better a check that fails the run if yesterday's or today's image is missing | **Open** |
| Backfill of the 113 missing days | All, last N days, or none. Cost is real (high-quality images), estimate before running | **Open** |
| Footer apps | FillariStatus certainly. Others (ThemeALot, ggplot2-extended-companion, survey explorer) only if they are live apps | **Open** |
| Text model | **`gpt-5.6-luna`**, reasoning off, JSON output (decided 2026-10-19 after the test in section 5) | **Decided**, not yet implemented |
| Image model | **`gpt-image-2.5-sunburst`, quality high** (decided 2026-10-19). Style becomes photographic instead of painterly; a style hint in the image prompt is still possible | **Decided**, not yet implemented |
| Theme | Keep the current look (black, silver, brand red `#C1272D`, EB Garamond). Decide whether to add a light mode (the other apps default to light, TuneTeller to dark) | **Open** |
| GCP project | Stay in `gallery-of-the-day-app` (isolation, as for TuneTeller) | Proposed |
| Order | Phase 0 first (restores the daily image), then Phase 1, review, then Phase 2 | Proposed |

## 3. Phase 0 — restore the daily run (small, do first)

1. **Re-enable** the workflow (`gh workflow enable`) and trigger it once (`gh workflow run`); verify in the run log and in Turso/R2 that the image for today exists. Per the repo rule: check the actual run status, don't assume.
2. **Keep-alive step** at the end of `r_scripts_daily.yml` (needs `actions: write` only for that job; replace `permissions: write-all` with the minimum). Verify it by reading the workflow state after a scheduled run.
3. **Backfill** per the user's decision, using the existing `R/backfill_date.R` (and note `R/backfill.R`, `backfill_2026.sh` are older variants to remove or merge in Phase 1). Run a single day first, look at the result with the user, then the rest.
4. Add a **missing-day check** (see 4.4) so this cannot happen silently again.

Note: the `R/create_prompt.R` and `R/fetch_image.R` retry fix (`17ee834`) is already in `main`.

## 4. Phase 1 — app and script code (one deploy)

### 4.1 Target structure (mirrors FillariStatus section 5)

```
app/
├── run.R              # entry point: port, security-headers wrapper
├── global.R           # libraries, sources www/*.R
├── ui.R               # theme, layout, footer (reads variables.R / strings.R)
├── server.R           # reactive logic only
└── www/
    ├── variables.R    # R2 URL, dates, brand colours, footer links
    ├── strings.R      # ALL user-facing text (caption, disclaimer, errors)
    ├── turso.R        # single copy (see 4.3)
    ├── functions.R    # pure helpers (caption formatting, image URL, date helpers)
    ├── security.R     # security headers + with_security_headers()
    ├── lightbox.js    # lightbox + keyboard navigation (now inline in ui.R)
    ├── styles.css  favicon.png
R/
├── config.R           # models, prompts, limits, shared by the scripts
├── openai.R           # never-throwing wrappers: text and image calls
├── create_prompt.R  fetch_image.R  check_missing_days.R  backfill_date.R
tests/testthat/
    fixtures/          # saved OpenAI and Turso responses (no keys)
    test-functions.R  test-openai.R  test-turso.R  test-security.R  test-server.R
```

Everything that exists today keeps working; the move is mechanical first, behaviour changes second, in separate commits.

### 4.2 Scripts (R/)
- **Models in one place** (`R/config.R`); remove the four hard-coded `gpt-4o-mini`/`gpt-image-1.5` strings. Prompts move there too.
- **One OpenAI helper** instead of three copy-pasted `request()` blocks: timeout, `req_retry` for transient errors (429, 5xx, plus network errors, which the current `is_transient` does not cover), clear errors.
- **Structured output** for the event text (JSON schema: title, date, description) instead of stripping `\n` from free text, if the model test supports it. Keep the caption cleaning for older rows.
- **`fetch_image.R` uses today's prompt** (`WHERE date = ?`), and stops with a clear error if there is none.
- **Reasoning/parameters:** GPT-5.4-family models reject `temperature`; use `reasoning: {effort: "none"}` as in TuneTeller (to be confirmed in the test).
- **Failure behaviour:** a failed day exits non-zero so the run is red; no swallowed errors (`tryCatch` blocks that only `cat()` are reviewed one by one). The "sanitise, then alternative event" fallback chain is kept (it is the content-safety net) but logged clearly.
- **No `source("secret.R")` fallback hidden in the scripts:** read config in one place, fail with a clear message when a variable is missing.
- Remove duplicates and dead scripts after checking they are unused: `R/backfill.R`, `backfill_2026.sh`, `R/deploy_app.R` (ShinyApps.io was removed from the workflow), `migrate_*.R` (one-off migrations, already done) — each deletion confirmed with the user.

### 4.3 App (app/)
- Split `ui.R`: footer from a shared list in `variables.R`, JavaScript into `www/lightbox.js`, text into `strings.R`.
- **Footer:** one list in `variables.R`, add FillariStatus (and others agreed in section 2); keep the cross-app format and "current app" exclusion.
- **One `turso.R`.** The app and the scripts must share one file (decide the location so the Docker image still contains it; the allowlist `.dockerignore` must include it).
- **States:** a never-throwing data layer for the app (as in FillariStatus): Turso unreachable, no prompts yet, date without a prompt, image missing in R2 (an `onerror` fallback instead of a broken image), instead of an R error page.
- **Stale-data banner:** if the newest prompt is older than N days, say so quietly (this problem would have been visible to visitors).
- Fix the date-picker JavaScript's reliance on `console.log` and Shiny binding internals only if it breaks; otherwise keep (it works, and is out of scope).
- **Security:** headers via `www/security.R` and the `run.R` wrapper (X-Frame-Options, CSP, Referrer-Policy, Permissions-Policy, HSTS, nosniff). CSP must allow the R2 public image host, Google Fonts (EB Garamond via `font_google`), and `wss:`; start report-only, enforce after a real-browser check. Gotcha from the sibling plans: wrap `app$httpHandler`, because `shiny.http.response.filter` does nothing.
- **Escaping:** captions come from the model and the DB; keep `tagList(text, tags$br())` and never `HTML()`. The lightbox builds HTML from `src`/`alt` with string concatenation: switch to DOM calls so a quote in an alt text cannot break out.
- **Cost/robustness of the DB read:** `prompts()` reads the whole table per session; cache it for a short time (it changes once a day).
- Remove the stray root-owned `app/app_cache/` if nothing needs it (check first).
- Copy and README: replace "GPT-4o-mini" in the disclaimer and README with the model(s) actually used, from `variables.R`.

### 4.4 Monitoring
- `R/check_missing_days.R`: compares the dates in Turso with the images in R2 for the last N days and fails (red run, email) if any is missing. Runs at the end of the daily workflow, and can run on its own schedule.

### 4.6 Fact accuracy (done for new days 2026-10-19, commit `219b829`; old days open)
Even `gpt-5.6-luna` invented events on hard dates (for example "first Antarctic iceberg sighting, 28 June 1828"), and answers vary from run to run. The model also repeated the date in the image text, which spread a wrong date into the picture.

**Fix (implemented):** `R/wikipedia.R` fetches the real events for the date from Wikipedia's "On this day" feed (`api.wikimedia.org/feed/v1/wikipedia/en/onthisday/events/MM/DD`, identified by a User-Agent with the app and repo URLs, no personal address). The model chooses one event by number and describes it; the year and event name come from the list. The prompt says to describe only what the entry says. The image prompt gets a "no text, letters, numbers, dates, captions, signs or logos" line (not stored with the caption), tested on the same caption with and without it: no lettering left, the scene as rich. Wikipedia is credited (CC BY-SA 4.0) in the app disclaimer, README and project page. Real-API test on 8 dates (28 June, 1 Oct, 19 Oct, 20 July, 9 Nov, 14 March, 1 Jan, 25 Dec): all picks were real, positive, with the right year. Tests: 22 tests, 70 expectations.

**Audit of the stored captions (2026-10-19, read-only, about US$0.20):** for each of the 292 days the caption was compared with that date's real list by `gpt-5.6-luna` (strict: same event and same year).

| Period | Matches a real event on its date |
|---|---|
| 2026-01-01 to 06-27 (gpt-4o-mini, daily job) | 63 of 178 (35%) |
| 2026-06-28 to 10-19 (backfill) | 30 of 114 (26%) |
| All | 93 of 292 (32%); 199 days do not match |

The match rate is a lower bound: the feed is not exhaustive, so a true event that is not on the list counts as a mismatch. In a random sample of 45 mismatches, most were clearly wrong (Poe "dies" on the date of his birth, a Sydney Opera House "inauguration" in 1967, Apollo 9 launched on the wrong day, Earth Day in September, "9/11 2001: ISS crew celebrates"), and a few were true or plausible (the death of Queen Victoria, Woodstock, Viking 1 arriving at Mars). That reading of the sample is the author's judgment, not a verified source. Five captions are about prohibited topics (a battle, treaties ending a war, two deaths).

**Done:** all mismatched days were regenerated (about US$0.055 each); see the status table.

### 4.5 Tests
- `testthat` 3 with `httr2::local_mocked_responses()`, no live calls. Cover: OpenAI wrapper (valid, malformed, empty, 429/5xx retry, timeout, content rejection and the fallback chain), Turso wrapper, prompt selection by date, caption helpers (the existing ones are pure and easy), image URL building, security headers and handler wrapper (plain, NULL, promised responses), `testServer()` for the date logic and the empty/missing states.
- Real-browser check (Chrome) before the deploy: latest image, picking an older date, arrow-key navigation, the lightbox, a date with no image, mobile width.
- `testServer()` doesn't step `debounce()`; avoid depending on it.

## 5. Model review

Done as a test with the user before anything is switched (as for TuneTeller):

| Step | Detail |
|---|---|
| Text | Same prompt, 3 or more dates (including a hard one like 1 January), `gpt-5.4-nano` vs `gpt-5.4-mini`, reasoning off. Compare: positivity rule kept (no war/violence), date accuracy, visual detail, length, latency, JSON validity, tokens |
| Image | Keep `gpt-image-1.5` high vs medium quality, and any newer image model the account lists. Compare look, rejection rate, cost per image |
| Cost | Measure tokens and image cost from the usage response; project the monthly total. The repo has April 2026 usage CSVs in `diagnosis/` (git-ignored) to compare against |
| Needs | The OpenAI key (not in `.env`; it is in `secret.R` and the GitHub secret). Ask the user before reading it; print only results |
| Switch | `models` in `R/config.R` is the one-line change; update README and UI disclaimer from the same value |

Known from the sibling work (secondary, unverified for this prompt): `gpt-5.4-nano` is about US$0.20 in / US$1.25 out per 1M tokens; `gpt-5.4-mini` US$0.75 / US$4.50. Text cost is negligible next to the image. Unlike TuneTeller, there is no Spotify-style parsing risk, but the caption text is shown to the public, so quality matters more than speed.

### 5.1 Test results (2026-10-19) and decision

Prices from developers.openai.com/api/docs/pricing; image costs are usage tokens x list price, **not checked against the billing page**. Facts in the captions were judged from general knowledge, not verified sources. Small sample: 5 dates (June 28, July 20, October 4, November 9, March 14), 1 run per cell, production prompt unchanged, `reasoning_effort: none` for the GPT-5.x models.

**Text** (right event on its date / cost per caption):

| Model | Correct | Cost | Notes |
|---|---|---|---|
| gpt-4o-mini (current) | 4/5 | $0.00024 | Invented "first Cessna 172 launch, 28 June 1969" (first flight was 1955) |
| gpt-5.4-nano | 2/5 | $0.00065 | Wrong Covent Garden, Michelin Guide and Apollo 12 dates; added meta text ("Selected event", "Category") |
| **gpt-5.6-luna** | **5/5** | **$0.00030** | Versailles 1919, Apollo 11, Sputnik, Apollo 4, Einstein |
| gpt-5.4-mini | 3/5 | $0.00128 | Invented a 28 June 1914 Olympic event |
| gpt-5.6-terra | 3-4/5 | $0.00342 | Wrong IOC date; picked the 1965 blackout (a disaster, against the rules) |

All GPT-5.x models wrote markdown headings and bold, so the text step must use structured JSON output (and the app must never show raw markdown).

**Image** (two captions, 1024x1024):

| Config | Cost per image | Time | Look |
|---|---|---|---|
| gpt-image-1.5 high (current) | $0.15 | 31 s | Soft, painterly, matches the existing 178 images |
| gpt-image-1.5 medium | $0.05 | 14 s | Same style, less detail |
| gpt-image-2 medium | $0.054 | 41 s | Sharp, photographic |
| gpt-image-2.5-flare medium | $0.014 | 14-17 s | Sharp, photographic |
| gpt-image-2.5-sunburst medium | $0.014 | 22 s | Sharp, a little richer |
| **gpt-image-2.5-sunburst high** | **$0.054** | 45 s | Sharpest; legible faces and name plates |
| gpt-image-1-mini medium | $0.009 | 12 s | Darkest, least detail |

Monthly: current about US$4.50, chosen setup about US$1.60. Caveats: the new models are photographic, so the images differ from the first 178 and can read as fake photographs; both sometimes invent text inside the image (for example a French banner). The disclaimer ("artistic interpretations, not historical photographs") stays.

**To do when implementing:** one JSON schema for the event (for example `date`, `year`, `title`, `description`) with the caption stored as plain text in the existing `text` column (no schema change); the same model for the sanitise and alternative-event fallbacks; update the UI disclaimer and README from the config values; check that `gpt-image-2.5-sunburst` uses the same request fields as `gpt-image-1.5` in the real scripts (the test used `size`, `quality`, `n` and the default base64 response, and worked).

## 6. Phase 2 — infrastructure (each step needs approval)

Mirrors TuneTeller section 5. All in the existing project `gallery-of-the-day-app`; first a read-only inventory.

1. **Inventory (read-only):** services (including stray failed ones from the February mis-deploys: `gallery-of-the-day-app` exists as a failed service in the `tuneteller-app` project), IAM on the compute account, secrets (the app reads `TURSO_*` and `R2_PUBLIC_URL` from Secret Manager), registry size, budget coverage.
2. **Runtime account** `gallery-runtime` with `secretAccessor` on the three secrets only; drop `roles/editor` from the compute account if present (keep `cloudbuild.builds.builder`).
3. **Keyless deploy:** Workload Identity pool `gallery` and provider restricted to `AnttiRask/gallery-of-the-day` on `refs/heads/main`; service account `gallery-deploy` with the narrow roles listed in the TuneTeller plan (5.2), including the custom `storage.buckets.list` role. Test by impersonation and by negative tests before switching the workflow on.
4. **Image:** `rocker/r-ver` (R version from `renv.lock`), system libraries from Posit's sysreqs API, `renv::restore()` from Posit Linux binaries, renv cache disabled, non-root user, `CMD Rscript app/run.R`, allowlist `.dockerignore` (never `.env`, `secret.R`). The lock has to be complete: regenerate it inside the target image (TuneTeller 5.3), and check every `Requirements` entry is in the lock. Compact (single-line) JSON is no longer required for the app image; **but** the daily GitHub workflow restores the same `renv.lock`: confirm that it still works (the project notes record a compact-JSON requirement for Actions) before changing the lock.
5. **Deploy settings:** `--timeout 3600 --session-affinity`, `--max-instances 3`, concurrency above the parallel asset count (do not lower it), no `--allow-unauthenticated` in the workflow (already public).
6. **Workflows:** `tests.yml` (tests on the locked packages) and `deploy_shiny_app.yml` (build, deploy, smoke test that checks the `git-sha` label), triggered on `app/**` and build files only; keep `r_scripts_daily.yml` separate, with the Phase 0 changes. Pin actions to SHAs, minimum `permissions`, Dependabot for Actions and Docker.
7. **Repo hygiene:** secret scanning, push protection, Dependabot alerts and security updates, `main` protected (no force-push or deletion), read back to verify.
8. **Cleanup:** Artifact Registry keeps the newest 5 versions; lifecycle on the build buckets.
9. **Websocket:** with the 3600 s timeout, `allowReconnect(TRUE)` does nothing on Cloud Run; use `"force"` only after checking the server logic is idempotent. Here it is read-only (a date pick), so `"force"` is safe to consider.

Phase 2 changes cloud resources; each numbered step is shown to the user first, and the live service is never touched until the new workflow is proven.

## 7. Verification (applies to every phase)

- After every commit/push: `git status`, `git ls-remote origin refs/heads/main` equals `HEAD`, and read the workflow run result from GitHub; never suppress error output in scripts that call GitHub or cloud APIs.
- After every deploy: check the revision and `git-sha` label, HTTP 200, the logs, and use the live app (newest image, an older date, lightbox, keyboard).
- Phase 0: confirm the workflow state is `active`, a scheduled (not manual) run happens, and today's image and prompt exist.
- If a fix fails, find the root cause and try a different approach rather than repeating it.

## 8. Order of work

1. Decide section 2 open items with the user.
2. Phase 0 (re-enable, keep-alive, one test day, backfill as decided).
3. Model test (section 5) and choice.
4. Phase 1 in small commits (mechanical move, then behaviour), reviewed locally with the running app (`docker compose up --build`, http://localhost:8083).
5. One deploy of Phase 1 (manual `./deploy.sh` still, until Phase 2).
6. Phase 2, step by step with approval.
7. Update `CLAUDE.md`, README, `DEPLOY.md`, and the project page `docs/index.html` (models, footer).

## 9. Handling secrets

- Never `cat`/`grep` secret files (`.env`, `secret.R`) or print env values; check key presence by name and test calls by HTTP status only.
- `.env` values may be quoted; parse them in a script rather than sourcing the file.
- Test scripts that call live APIs read keys from the environment and print results only.

## 10. Out of scope / known

- Content policy stays as in `CLAUDE.md` (positive events only; sanitise, then alternative event on rejection).
- Phones, Safari and Firefox are not covered by the real-browser checks unless the user can test them.
- R packages are updated by regenerating `renv.lock` inside the image, not by Dependabot.
- Cold start (`min-instances` 0) stays as is unless the user decides otherwise.
