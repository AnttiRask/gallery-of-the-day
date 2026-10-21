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

# Deploy to Google Cloud Run
./deploy.sh

# Restore R packages after clone
R -e "renv::restore()"
```

## Architecture

### Data Flow
1. **Prompt Generation** (`R/create_prompt.R`): `R/wikipedia.R` fetches the real events for the date from Wikipedia's "On this day" feed; GPT-5.6 Luna chooses one by number and describes it (JSON output; the year and event come from the list, not from the model; stored as plain text in Turso, a libSQL database)
2. **Image Generation** (`R/fetch_image.R`): GPT Image 2.5 Sunburst creates images (a "no text in the image" line is added to the prompt, not to the stored caption), uploaded to Cloudflare R2
3. **Shared code**: `R/config.R` (models, prompts) and `R/openai.R` (API calls, retries, fallbacks) are used by `create_prompt.R`, `fetch_image.R` and `backfill_date.R`; tests are in `tests/testthat/`
3. **Display** (`app/`): Shiny app fetches prompts from Turso and images from R2

### Key Components

- `R/turso.R` - The one Turso HTTP client, shared by the daily scripts and the app (`app/global.R` sources `../R/turso.R`; the `Dockerfile` copies just this file into the image, and `.dockerignore` allows it). `turso_query()` (reads: 8 s timeout, one retry on network errors, 429 and 5xx, not on other 4xx) and `turso_execute()` (writes: 30 s timeout, **never retried**: `prompts_archive` has no unique key, so a retried insert could duplicate a row, and a retried insert into `prompts`, whose `date` is UNIQUE, would fail with a confusing error). Credentials come from the `TURSO_DATABASE_URL` and `TURSO_AUTH_TOKEN` environment variables, or variables of the same name (the app's `config.R`); nothing passes them as arguments. Verified against the old code: the same requests byte for byte
- `app/server.R` - Shiny server logic, fetches prompts reactively, sends available dates to client for keyboard navigation
- `app/ui.R` - Shiny UI with bslib/Bootstrap 5 theming, includes lightbox and keyboard navigation JavaScript
- `app/www/functions.R` - Helper functions including `clean_and_break_text()` for caption formatting
- `app/www/security.R` - Security headers (CSP, X-Frame-Options, nosniff, Referrer-Policy, Permissions-Policy, HSTS); `app/run.R` wraps the app's `httpHandler` with them
- `app/global.R` - Loaded by Shiny before `ui.R` and `server.R`: the libraries and the `source()` calls for `../R/turso.R`, `www/variables.R`, `strings.R`, `functions.R`, `data.R` and `config.R`. The Docker image has only shiny, bslib, dplyr, stringr, httr2 and jsonlite, so the app code must not use other packages (for example purrr).
- `app/www/variables.R` - Settings shared by `run.R`, `config.R` and `ui.R`: the default R2 public URL, brand colours, the font URL and the footer's app list
- `app/www/strings.R` - All user-facing text (title, labels, disclaimer, error-state messages)
- `app/www/data.R` - `load_prompts()`, the app's never-throwing data layer: returns `ok`, `empty` or `unavailable`; the real error goes to the log, visitors see a message (`state_message()` in `functions.R`) and, when unavailable, a "Try again" button. `turso_request()` in `R/turso.R` sets the read timeout and retry; httr2's mocking skips the retry loop, so the retries were verified against a local server that answers 500 then 200, and the unit tests check the request's policy instead. A missing image is swapped for a message by `lightbox.js`. `stale_note()` (`functions.R`) adds a quiet note above the image when the newest image is more than `stale_after_days` (2, in `variables.R`) old; it is 2 and not 1 because GitHub sometimes starts the 04:00 UTC run hours late. The prompts are cached in memory per instance (`load_prompts()` wraps `fetch_prompts()`): a copy is used for 5 minutes (`prompts_cache_seconds`); if Turso then fails, the old copy is served for up to 7 days (`prompts_max_age_seconds`) and Turso is left alone for 30 s (`prompts_retry_seconds`); only a good result replaces the cache, never an empty table; `global.R` fills the cache shortly after start with `later::later()`. The three settings can be overridden with the options `gallery.prompts_cache_seconds`, `gallery.prompts_retry_seconds` and `gallery.prompts_max_age_seconds` (for tests). `global.R` sets `shiny.sanitize.errors`, so any other error shows Shiny's generic message.
- `app/www/health.R` - `GET /health` for the uptime monitor (`with_health_check()`, wrapped in `run.R` inside the security headers). 200 `ok`, or 503 with a short reason: `unavailable` (no prompts and no cached copy), `empty`, `stale` (the newest image is more than `health_max_age_days` = 1 day old: a whole day was missed), `degraded` (the cached copy is being served because refreshes fail). It exists because `/` returns 200 even when Turso is down or the daily job has failed, and the prompts cache hides a Turso outage from visitors. The answer carries no error details. It is `/health` and not `/healthz` because Google's frontend may reserve `/healthz`.
- `app/www/lightbox.js` - Lightbox and arrow-key date navigation (it was inline in `ui.R`). The lightbox is built with DOM calls, not string concatenation, so a quote in the alt text can't inject markup (proved in Chrome: the old code let a hostile alt add a `<b>` and a second `<img>`; the new code doesn't). The page, including the `?v=` version of each asset, is built once when the app starts, so restart the app after changing a file in `www/`.
- Everything in `app/www/` is served publicly: never put a secret in it
- `app/www/mode-toggle.js` - Light/dark switch (dark default)

### Infrastructure

- **Database**: Turso (libSQL) stores prompts with date and text columns
- **Image Storage**: Cloudflare R2 with public URL, images named `gallery-of-the-day-{YYYY-MM-DD}.png`
- **Hosting**: Google Cloud Run (production) or Docker Compose (development)
- **Identities**: the service runs as `gallery-runtime` (reads only its 3 secrets), `--max-instances 3`. `roles/editor` is gone from the compute account. `.github/workflows/deploy_shiny_app.yml` (manual) deploys keylessly as `gallery-deploy` through Workload Identity (pool `gallery`, `main` only); details in `DEPLOY.md`. The build must be `--async` plus polling, because that account can't stream build logs.
- **Automation**: GitHub Actions runs daily at 4 AM UTC (`.github/workflows/r_scripts_daily.yml`)
- **Image**: `Dockerfile` uses `rocker/r-ver:4.5.2` (the R version in `renv.lock`) and runs as the non-root user `gallery`. It restores only the packages the app needs (shiny, bslib, dplyr, stringr, httr2, jsonlite, renv, plus dependencies) from Posit's Linux binaries; the daily scripts' packages stay in the lockfile for GitHub Actions. `.dockerignore` is an allowlist, and `.env`, `.Renviron` and `secret.R` never enter the image. Build and run locally: `docker compose up --build` (http://localhost:8083).
- **Security headers**: `www/security.R` sets an enforced CSP that allows exactly the fonts host (`fonts.cdnfonts.com`) and the R2 host the images come from (derived from `R2_PUBLIC_URL`; a value that isn't an `https://` URL stops the start, so Cloud Run keeps the previous revision). No `'unsafe-eval'`. Tested in Chrome with a violation recorder as the first script in `<head>` (prove the recorder first with a foreign image or script): the full app (date picker, arrow keys, lightbox, theme switch) produced zero real violations. One report is expected and harmless: Shiny 1.12.1 calls `setTimeout(undefined, 0)` after rendering dynamic output (`shiny.min.js`), which the browser treats as a code string. Rancher Desktop can't bind-mount `/tmp`, so mount test copies from under the home directory.
- **Reconnects**: Cloud Run closes a page's websocket at the request `--timeout` (it was 300 s, so the page greyed out after 5 minutes). `deploy.sh` now sets `--timeout 3600` (the maximum) and `--session-affinity`, and `server.R` calls `session$allowReconnect("force")`. `TRUE` does nothing on Cloud Run: the client only reconnects if the host (Shiny Server, Posit Connect) allows it too. With `"force"` a new session starts and the browser re-sends its inputs (the selected date survives); keep everything behind an input read-only, because a reconnect re-runs it. Tested by closing the socket in a browser: reconnected in about 2.5 s with the line, stayed disconnected without it.

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
