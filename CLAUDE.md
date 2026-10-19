# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Gallery of the Day is an R/Shiny web app that displays daily AI-generated images inspired by historical events. Each day, GPT-5.6 Luna researches a positive historical event and GPT Image 2.5 Sunburst creates a high-quality image based on that description. (The models are set in `R/config.R`; days before 2026-10-19 used GPT-4o-mini and GPT Image 1.5.)

## Development Commands

```bash
# Local development with Docker (hot-reload enabled for app/ directory)
docker compose up --build
# App available at http://localhost:8083

# Run automation scripts locally (requires .env or secret.R with credentials)
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

- `R/turso.R` - Turso HTTP API wrapper with `turso_query()` and `turso_execute()` functions
- `app/server.R` - Shiny server logic, fetches prompts reactively, sends available dates to client for keyboard navigation
- `app/ui.R` - Shiny UI with bslib/Bootstrap 5 theming, includes lightbox and keyboard navigation JavaScript
- `app/www/functions.R` - Helper functions including `clean_and_break_text()` for caption formatting
- `app/www/security.R` - Security headers (CSP, X-Frame-Options, nosniff, Referrer-Policy, Permissions-Policy, HSTS); `app/run.R` wraps the app's `httpHandler` with them
- `app/www/variables.R` - Settings shared by `run.R` and `config.R` (the default R2 public URL)
- `app/www/mode-toggle.js` - Light/dark switch (dark default)

### Infrastructure

- **Database**: Turso (libSQL) stores prompts with date and text columns
- **Image Storage**: Cloudflare R2 with public URL, images named `gallery-of-the-day-{YYYY-MM-DD}.png`
- **Hosting**: Google Cloud Run (production) or Docker Compose (development)
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

For local development, credentials can be placed in `secret.R` (gitignored) or `.env`.

## Content Guidelines

The prompt generation strictly focuses on positive historical events:
- Scientific discoveries, cultural celebrations, artistic achievements, sports, space exploration
- Explicitly excludes wars, battles, violence, weapons, tragedies, political controversies

If the image API's safety system blocks a prompt (`moderation_blocked`), `fetch_image.R` rewrites it (also removing brand names and trademarked characters) or requests an alternative event. Other API errors, such as an empty OpenAI balance or an invalid key, stop the run with OpenAI's own message.
