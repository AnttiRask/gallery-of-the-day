# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Gallery of the Day is an R/Shiny web app that displays daily AI-generated images inspired by historical events. Each day, GPT-4o-mini researches a positive historical event and GPT Image 1.5 creates an HD image based on that description.

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
1. **Prompt Generation** (`R/create_prompt.R`): GPT-4o-mini generates historical event descriptions, stored in Turso (libSQL database)
2. **Image Generation** (`R/fetch_image.R`): GPT Image 1.5 creates images, uploaded to Cloudflare R2
3. **Display** (`app/`): Shiny app fetches prompts from Turso and images from R2

### Key Components

- `R/turso.R` - Turso HTTP API wrapper with `turso_query()` and `turso_execute()` functions
- `app/server.R` - Shiny server logic, fetches prompts reactively, sends available dates to client for keyboard navigation
- `app/ui.R` - Shiny UI with bslib/Bootstrap 5 theming, includes lightbox and keyboard navigation JavaScript
- `app/www/functions.R` - Helper functions including `clean_and_break_text()` for caption formatting

### Infrastructure

- **Database**: Turso (libSQL) stores prompts with date and text columns
- **Image Storage**: Cloudflare R2 with public URL, images named `gallery-of-the-day-{YYYY-MM-DD}.png`
- **Hosting**: Google Cloud Run (production) or Docker Compose (development)
- **Automation**: GitHub Actions runs daily at 4 AM UTC (`.github/workflows/r_scripts_daily.yml`)

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

If DALL-E rejects a prompt, `fetch_image.R` automatically sanitizes it or requests an alternative event.
