# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Gallery of the Day is an R/Shiny web app that displays daily AI-generated images inspired by historical events. Each day, GPT-5.6 Luna researches a positive historical event and GPT Image 2.5 Sunburst creates a high-quality image based on that description. (The models are set in `R/config.R`; days before 2026-10-19 used GPT-4o-mini and GPT Image 1.5.)

## Development Commands

```bash
# Local development with Docker (hot-reload enabled for app/ directory)
docker compose up --build
# App available at http://localhost:8083

# Run automation scripts locally (requires the credentials as environment variables, e.g. in .Renviron)
Rscript R/create_prompt.R    # Generate today's historical event prompt
Rscript R/fetch_image.R      # Create and upload today's image

# Deploy to Google Cloud Run (normally a push to main does this by itself; see Automation)
./deploy.sh

# Restore R packages after clone
R -e "renv::restore()"
```

## Architecture

### Data Flow
1. **Prompt Generation** (`R/create_prompt.R`): `R/wikipedia.R` fetches the real events for the date from Wikipedia's "On this day" feed; GPT-5.6 Luna chooses one by number and describes it (JSON output; the year and event come from the list, not from the model; stored as plain text in Turso, a libSQL database)
2. **Image Generation** (`R/fetch_image.R`): GPT Image 2.5 Sunburst creates images (a "no text in the image" line is added to the prompt, not to the stored caption), uploaded to Cloudflare R2
3. **Shared code**: `R/config.R` (models, prompts) and `R/openai.R` (API calls, retries, fallbacks) are used by `create_prompt.R`, `fetch_image.R` and `backfill_date.R`. The three scripts only read the environment, load packages and call the flows in `R/daily.R` (`create_daily_prompt()`, `fetch_daily_image()`, `backfill_day()`), which take Turso, R2 (`r2_client()` in `R/r2.R`) and OpenAI as arguments, so `tests/testthat/test-daily.R` runs every path (skip, create, safety-block rewrite, regenerate, failures) with fakes and the order of writes is checked (Turso update before the upload; `--regenerate` updates Turso last). Tests are in `tests/testthat/`. To try a script locally without touching production, use `Rscript --no-environ` with fake variables: R reads the project's `.Renviron` otherwise and the real credentials override yours
3. **Display** (`app/`): Shiny app fetches prompts from Turso and images from R2

### Key Components

- `R/turso.R` - The one Turso HTTP client, shared by the daily scripts and the app (`app/global.R` sources `../R/turso.R`; the `Dockerfile` copies just this file into the image, and `.dockerignore` allows it). `turso_query()` (reads: 8 s timeout, one retry on network errors, 429 and 5xx, not on other 4xx) and `turso_execute()` (writes: 30 s timeout, **never retried**: `prompts_archive` has no unique key, so a retried insert could duplicate a row, and a retried insert into `prompts`, whose `date` is UNIQUE, would fail with a confusing error). Credentials come from the `TURSO_DATABASE_URL` and `TURSO_AUTH_TOKEN` environment variables, or variables of the same name (the app's `config.R`); nothing passes them as arguments. Verified against the old code: the same requests byte for byte
- `app/server.R` - Shiny server logic, fetches prompts reactively, sends available dates to client for keyboard navigation
- `app/ui.R` - Shiny UI with bslib/Bootstrap 5 theming, includes lightbox and keyboard navigation JavaScript
- `app/lib/functions.R` - Helper functions including `clean_and_break_text()` for caption formatting. `add_spaces_after_periods()` only adds the space the model sometimes leaves between sentences (`end.Next`, `end.**Heading**`): a period between a lowercase letter, digit or closing quote/bracket and a capital, or before a bold heading. Decimals (`3.5`), initials (`U.S.`, `D.C.`), domain names and a period before a closing quote are left alone; the first version spaced every period and broke 21 of the 306 captions (fixed 2026-11-03 after comparing old and new output on all of them). `insert_row_breaks()` never puts a paragraph break before the first sentence (a first sentence over 400 characters used to leave a blank paragraph above the caption; fixed 2026-11-03)
- `app/lib/security.R` - Security headers (CSP, X-Frame-Options, nosniff, Referrer-Policy, Permissions-Policy, HSTS); `app/run.R` wraps the app's `httpHandler` with them
- `app/global.R` - Loaded by Shiny before `ui.R` and `server.R`: the libraries and the `source()` calls for `../R/turso.R`, `lib/variables.R`, `strings.R`, `functions.R`, `data.R` (the app's R code lives in `app/lib/`, not in `www/`) and `config.R`. The Docker image has only shiny, bslib, dplyr, stringr, httr2 and jsonlite, so the app code must not use other packages (for example purrr).
- `app/lib/variables.R` - Settings shared by `run.R`, `config.R` and `ui.R`: the default R2 public URL, brand colours, the font URL and the footer's app list
- `app/lib/strings.R` - All user-facing text (title, labels, disclaimer, error-state messages)
- `app/lib/data.R` - `load_prompts()`, the app's never-throwing data layer: returns `ok`, `empty` or `unavailable`; the real error goes to the log, visitors see a message (`state_message()` in `functions.R`) and, when unavailable, a "Try again" button. `turso_request()` in `R/turso.R` sets the read timeout and retry; httr2's mocking skips the retry loop, so the retries were verified against a local server that answers 500 then 200, and the unit tests check the request's policy instead. A missing image is swapped for a message by `lightbox.js`. `stale_note()` (`functions.R`) adds a quiet note above the image when the newest image is more than `stale_after_days` (2, in `variables.R`) old; it is 2 and not 1 because GitHub sometimes starts the 04:00 UTC run hours late. The prompts are cached in memory per instance (`load_prompts()` wraps `fetch_prompts()`): a copy is used for 5 minutes (`prompts_cache_seconds`); if Turso then fails, the old copy is served for up to 7 days (`prompts_max_age_seconds`) and Turso is left alone for 30 s (`prompts_retry_seconds`); only a good result replaces the cache, never an empty table; `global.R` fills the cache shortly after start with `later::later()`. The three settings can be overridden with the options `gallery.prompts_cache_seconds`, `gallery.prompts_retry_seconds` and `gallery.prompts_max_age_seconds` (for tests). `global.R` sets `shiny.sanitize.errors`, so any other error shows Shiny's generic message.
- `app/lib/health.R` - `GET /health` for the uptime monitor (`with_health_check()`, wrapped in `run.R` inside the security headers). 200 `ok`, or 503 with a short reason: `unavailable` (no prompts and no cached copy), `empty`, `stale` (the newest image is more than `health_max_age_days` = 1 day old: a whole day was missed), `degraded` (the cached copy is being served because refreshes fail). It exists because `/` returns 200 even when Turso is down or the daily job has failed, and the prompts cache hides a Turso outage from visitors. The answer carries no error details. It is `/health` and not `/healthz` because Google's frontend may reserve `/healthz`.
- `app/www/lightbox.js` - Lightbox and arrow-key date navigation (it was inline in `ui.R`). The lightbox is built with DOM calls, not string concatenation, so a quote in the alt text can't inject markup (proved in Chrome: the old code let a hostile alt add a `<b>` and a second `<img>`; the new code doesn't). The page, including the `?v=` version of each asset, is built once when the app starts, so restart the app after changing a file in `www/`.
- Only `app/www/` is served to browsers (`lightbox.js`, `mode-toggle.js`, `styles.css`, the favicon). The app's R files used to be in `www/` too, so `/data.R`, `/security.R` and the others were public (no secrets, but the logic and the CSP were readable); they moved to `app/lib/` on 2026-11-03 and now return 404. Never put an R file or a secret in `www/`: `tests/testthat/test-app-static.R` fails if one appears there
- `app/www/mode-toggle.js` - Light/dark switch (dark default)

### Infrastructure

- **Database**: Turso (libSQL) stores prompts with date and text columns
- **Image Storage**: Cloudflare R2 with public URL, images named `gallery-of-the-day-{YYYY-MM-DD}.png`
- **Hosting**: Google Cloud Run (production) or Docker Compose (development)
- **Identities**: the service runs as `gallery-runtime` (reads only its 3 secrets), `--max-instances 3`. `roles/editor` is gone from the compute account, and since 2026-11-07 so is its access to the secrets (only `gallery-runtime` reads them). `.github/workflows/deploy_shiny_app.yml` (on pushes to `main` that change the image's files, and on demand; the tests run first) deploys keylessly as `gallery-deploy` through Workload Identity (pool `gallery`, `main` only); details in `DEPLOY.md`. The build must be `--async` plus polling, because that account can't stream build logs.
- **Monitoring**: a Cloud Monitoring uptime check on `/health` (every 5 minutes, 6 regions) and an alert policy that emails the owner when it fails for 10 minutes; details in `DEPLOY.md`, policy in `monitoring/health-alert-policy.json`.
- **Automation**: GitHub Actions runs daily, scheduled for 4 AM UTC (`.github/workflows/r_scripts_daily.yml`); GitHub starts it between about 08:30 and 10:30 UTC, so "today's image doesn't exist yet" is normal until then. A second job, `report`, runs after the daily job: if it failed it opens an issue labelled `daily-run-failed` and assigned to the owner (GitHub emails the assignee at once; failures while it is open only add a comment) and the next successful run comments and closes it, so a failed day is noticed within minutes instead of through the `/health` staleness alert about a day later (tested on a throwaway branch with a simulated failure, a second failure and a success; the `/health` alert stays as the backup, for example when the schedule doesn't run at all). `tests.yml` runs the suite on every push and pull request; `backfill.yml` is manual. `deploy_shiny_app.yml` calls the tests first (`needs: tests`) and deploys only if they pass; it runs on pushes to `main` that touch `app/**`, `R/turso.R`, `Dockerfile`, `.dockerignore`, `.Rprofile`, `renv.lock`, `renv/activate.R`, `renv/settings.json` or the workflow itself (docs, tests and the other workflows don't deploy), and on demand. `tests.yml` is callable (`workflow_call`) and its concurrency group includes the caller's workflow name, so a called run and the push-triggered run of the same commit don't cancel each other. The smoke test checks the `git-sha` label and HTTP 200, but `gcloud run deploy` has already moved traffic by then: roll back with a traffic switch if a bad revision gets through. The R workflows (daily, tests, backfill) are pinned to `ubuntu-26.04` instead of `ubuntu-latest`: the label moved to 26.04 on 2026-10-31 and the then-locked `later` 1.4.5 didn't compile there (glibc 2.43 / GCC 15), which stopped the 2026-10-31 run; `renv.lock` has `later` 1.4.8 now (tested on 26.04: full restore and all tests). Test the same way before moving to a newer Ubuntu. The deploy workflow stays on `ubuntu-24.04`, like the Docker image. To read a run's log when `gh run view --log` comes back empty, use `gh api repos/{owner}/{repo}/actions/jobs/<job id>/logs` and the check-run annotations
- **Image**: `Dockerfile` uses `rocker/r-ver:4.5.2` (the R version in `renv.lock`) and stays on R 4.5 on purpose: moving to R 4.6 needs the lockfile rebuilt in a 4.6 container (`rlang` >= 1.3.0; the locked 1.1.7 doesn't compile on 4.6, so the Dependabot bump failed the build) and `r-version` changed in the workflows; Dependabot ignores `rocker/r-ver` minor and major bumps and runs as the non-root user `gallery`. It restores only the packages the app needs (shiny, bslib, dplyr, stringr, httr2, jsonlite, renv, plus dependencies) from Posit's Linux binaries; the daily scripts' packages stay in the lockfile for GitHub Actions. `.dockerignore` is an allowlist, and `.env`, `.Renviron` and `secret.R` never enter the image. Build and run locally: `docker compose up --build` (http://localhost:8083).
- **Security headers**: `lib/security.R` sets an enforced CSP that allows exactly the fonts host (`fonts.cdnfonts.com`) and the R2 host the images come from (derived from `R2_PUBLIC_URL`; a value that isn't an `https://` URL stops the start, so Cloud Run keeps the previous revision). No `'unsafe-eval'`. Tested in Chrome with a violation recorder as the first script in `<head>` (prove the recorder first with a foreign image or script): the full app (date picker, arrow keys, lightbox, theme switch) produced zero real violations. One report is expected and harmless: Shiny 1.12.1 calls `setTimeout(undefined, 0)` after rendering dynamic output (`shiny.min.js`), which the browser treats as a code string. Rancher Desktop can't bind-mount `/tmp`, so mount test copies from under the home directory.
- **Reconnects**: Cloud Run closes a page's websocket at the request `--timeout` (it was 300 s, so the page greyed out after 5 minutes). `deploy.sh` now sets `--timeout 3600` (the maximum) and `--session-affinity`, and `server.R` calls `session$allowReconnect("force")`. `TRUE` does nothing on Cloud Run: the client only reconnects if the host (Shiny Server, Posit Connect) allows it too. With `"force"` a new session starts and the browser re-sends its inputs (the selected date survives); keep everything behind an input read-only, because a reconnect re-runs it. Tested by closing the socket in a browser: reconnected in about 2.5 s with the line, stayed disconnected without it. **When the reconnect fails** (server down; checked 2026-11-03 against a local copy killed mid-session, `reconnect-fail.mjs`): Shiny keeps showing its own greyed page with "Attempting to reconnect... Try now" and retries without giving up (90 s+ observed); the image and caption stay visible, and the page reconnected by itself about 21 s after the server returned, on the same date. So no custom session-end message is needed. `lightbox.js` ignores arrow keys while `Shiny.shinyapp.isConnected()` is false (before, they changed the date box but not the image; a test checks the guard is present). Not tested: a client that loses its network.

## Environment Variables

Required for automation scripts:
- `OPENAI_API_KEY` - OpenAI API access
- `TURSO_DATABASE_URL`, `TURSO_AUTH_TOKEN` - Turso database
- `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET_NAME` - Cloudflare R2

Required for Shiny app:
- `R2_PUBLIC_URL` - Public URL for R2 bucket
- `TURSO_DATABASE_URL`, `TURSO_AUTH_TOKEN` - Turso database

For local development, put the credentials in `.Renviron` (scripts) or `.env` (Docker Compose). There is no `secret.R` any more; the scripts stop with a clear message if `OPENAI_API_KEY` is missing.

## Content Guidelines

The prompt generation strictly focuses on positive historical events:
- Scientific discoveries, cultural celebrations, artistic achievements, sports, space exploration
- Explicitly excludes wars, battles, violence, weapons, tragedies, political controversies

If the image API's safety system blocks a prompt (`moderation_blocked`), `fetch_image.R` rewrites it (also removing brand names and trademarked characters) or requests an alternative event. Other API errors, such as an empty OpenAI balance or an invalid key, stop the run with OpenAI's own message.
