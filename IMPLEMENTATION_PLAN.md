# Gallery of the Day - Implementation Plan

## Overview

This plan outlines the steps to revive and modernize the Gallery of the Day Shiny app. The goal is to get the daily automation working reliably while keeping costs minimal.

**Current State:** App last updated December 2023, automation broken due to GitHub Actions timeouts and deprecated API usage.

**Target State:** Fully automated daily updates, modern API integration, reliable deployment to ShinyApps.io.

---

## Phase 0: Preparation & Cleanup

### 0.1 Create New API Credentials

**OpenAI API Key:**
1. Go to https://platform.openai.com/api-keys
2. Create a new API key
3. Store locally in `secret.R` (gitignored):
   ```r
   OPENAI_API_KEY <- "sk-..."
   ```
4. Update GitHub repository secret: Settings → Secrets → `OPENAI_API_KEY`

**ShinyApps.io Credentials:**
1. Go to https://www.shinyapps.io/admin/#/tokens
2. Click "Add Token" to generate new credentials
3. Store locally in `secret.R`:
   ```r
   SHINY_APPS_NAME <- "youcanbeapirate"
   SHINY_APPS_TOKEN <- "..."
   SHINY_APPS_SECRET <- "..."
   ```
4. Update GitHub repository secrets:
   - `SHINY_APPS_NAME`
   - `SHINY_APPS_TOKEN`
   - `SHINY_APPS_SECRET`

### 0.2 Delete Old Images and Data

Remove the old 2023 content to start fresh:

```bash
# Delete old images (14 files from December 2023)
rm app/img/gallery-of-the-day-*.png

# Clear the prompts CSV (keep header only)
# Will recreate with new content
```

**Files to delete:**
- `app/img/gallery-of-the-day-2023-12-06.png` through `gallery-of-the-day-2023-12-19.png`
- Clear rows in `app/data/prompts.csv` (keep structure)

### 0.3 Clear Error Log

```bash
# Reset error log
> error_log.txt
```

---

## Phase 1: Update OpenAI API Integration

### 1.1 Migrate create_prompt.R to Chat Completions API

**Why:** The `gpt-3.5-turbo-instruct` model uses the legacy Completions API which is being phased out. The Chat Completions API is the standard going forward.

**Changes to `create_prompt.R`:**

```r
# OLD (Completions API - deprecated)
request(base_url) %>%
  req_url_path_append("completions") %>%
  req_body_json(list(
    model = "gpt-3.5-turbo-instruct",
    prompt = prompt,
    max_tokens = 4000,
    temperature = 0,
    n = 1
  ))

# NEW (Chat Completions API)
request(base_url) %>%
  req_url_path_append("chat/completions") %>%
  req_body_json(list(
    model = "gpt-4o-mini",
    messages = list(
      list(role = "system", content = "You are a historian providing vivid descriptions of historical events."),
      list(role = "user", content = prompt)
    ),
    max_tokens = 4000,
    temperature = 0.7
  ))
```

**Model choice:** `gpt-4o-mini` is recommended because:
- Cheaper than `gpt-3.5-turbo` ($0.15 vs $0.50 per 1M input tokens)
- Better quality outputs
- Actively maintained and improved

**Response parsing change:**

```r
# OLD
response$choices[[1]]$text

# NEW
response$choices[[1]]$message$content
```

### 1.2 Review fetch_image.R

The DALL-E 3 integration looks correct, but we should:
- Verify the API endpoint is still current
- Increase retry delays for better reliability
- Add more detailed error logging

**Current retry logic is good**, but consider increasing:
- Initial delay: 60 seconds → 90 seconds
- Backoff multiplier: Keep at 2x
- Max retries: Keep at 3

---

## Phase 2: Fix GitHub Actions Workflow

### 2.1 Switch to Ubuntu Runner

**Why:** Windows runners are slower and have more connection issues. Linux is faster and more reliable for API calls.

**Change in `r_scripts_daily.yml`:**

```yaml
# OLD
runs-on: windows-latest

# NEW
runs-on: ubuntu-latest
```

### 2.2 Increase Timeouts

**Why:** DALL-E 3 image generation can take 30-60 seconds, and with retries, the current 10-minute timeout is too tight.

```yaml
# OLD
timeout-minutes: 10

# NEW
timeout-minutes: 20
```

### 2.3 Improve Workflow Structure

Split into separate jobs for better visibility and failure isolation:

```yaml
jobs:
  generate-content:
    runs-on: ubuntu-latest
    steps:
      - Create prompt
      - Fetch image
      - Commit and push changes

  deploy:
    needs: generate-content
    runs-on: ubuntu-latest
    steps:
      - Deploy to ShinyApps.io
```

### 2.4 Add Better Error Handling

- Continue on prompt generation failure (skip that day)
- Add workflow status badges to README
- Send notification on repeated failures (optional)

---

## Phase 3: Code Quality Improvements

### 3.1 Consolidate API Configuration

Create a shared configuration approach:

```r
# In a shared config or at top of scripts
OPENAI_CONFIG <- list(
  base_url = "https://api.openai.com/v1",
  text_model = "gpt-4o-mini",
  image_model = "dall-e-3",
  image_size = "1024x1024"
)
```

### 3.2 Improve Error Logging

Current `error_log.txt` is minimal. Enhance to include:
- Full error messages
- Request details (without API key)
- Timestamp with timezone

### 3.3 Date Handling

In `fetch_image.R`, images are saved with `today() - 1`. This handles timezone differences between when the GitHub Actions workflow runs (4 AM UTC) and the intended display date. **Keep as-is** but add a comment explaining this:

```r
# Using yesterday's date because workflow runs at 4 AM UTC
# This ensures the image is associated with the correct calendar day
file_name <- str_c("app/img/gallery-of-the-day-", today() - 1, ".png")
```

---

## Phase 4: Testing and Validation

### 4.1 Local Testing Checklist

Before pushing changes, test locally:

1. [ ] Set `OPENAI_API_KEY` environment variable
2. [ ] Run `create_prompt.R` - verify prompt saved to CSV
3. [ ] Run `fetch_image.R` - verify image downloaded to `app/img/`
4. [ ] Run Shiny app locally - verify new content displays
5. [ ] Check date picker shows new date

### 4.2 Staged Rollout

1. **Day 1:** Push API changes, test with manual workflow trigger
2. **Day 2:** Monitor automated run at 4 AM UTC
3. **Day 3-5:** Verify stability across multiple runs
4. **Day 7:** Consider the migration complete if no failures

---

## Phase 5: Image Storage Migration to Cloudflare R2

**Priority:** Implement after app is running successfully

### 5.1 Why Cloudflare R2?

| Feature | Cloudflare R2 |
|---------|---------------|
| Free tier | 10 GB storage, 10M reads/month |
| Egress fees | None (this is the big advantage) |
| S3 compatible | Works with existing S3 tools/libraries |
| Global CDN | Fast delivery worldwide |

### 5.2 Migration Steps (Future)

1. Create Cloudflare account and R2 bucket
2. Generate R2 API credentials
3. Modify `fetch_image.R` to upload to R2 instead of local file
4. Modify `server.R` to load images from R2 URL
5. Update GitHub Actions with R2 credentials
6. Remove images from Git repository

### 5.2 Prompt Improvements

Current prompt sometimes generates war/political events. Consider adding guidance:

```
"Please focus on scientific discoveries, cultural milestones,
or positive human achievements when possible."
```

### 5.3 App Enhancements (from your to-do.txt)

- [ ] Add "About this project" tab
- [ ] Add "About me" tab
- [ ] Improve mobile responsiveness
- [ ] Add social sharing buttons

---

## Implementation Order

| Step | Task | Risk |
|------|------|------|
| 0a | Create new OpenAI API key | Low |
| 0b | Create new ShinyApps.io tokens | Low |
| 0c | Delete old images and clear prompts.csv | Low |
| 1 | Update `create_prompt.R` to Chat API | Low |
| 2 | Update GitHub Actions workflow | Low |
| 3 | Test locally with new credentials | Low |
| 4 | Update GitHub Secrets | Low |
| 5 | Push changes and trigger manual workflow run | Medium |
| 6 | Monitor automated runs for 3-5 days | Low |
| 7 | Migrate to Cloudflare R2 (after stable) | Low |

---

## Files to Modify

1. **`app/img/*.png`** - Delete all old images (14 files)
2. **`app/data/prompts.csv`** - Clear old entries, keep header row
3. **`create_prompt.R`** - Migrate to Chat Completions API
4. **`.github/workflows/r_scripts_daily.yml`** - Fix runner and timeouts
5. **`fetch_image.R`** - Add comment explaining date logic (optional)
6. **`error_log.txt`** - Clear old errors

---

## Rollback Plan

If the new implementation fails:

1. Revert to previous commit: `git revert HEAD`
2. The old Completions API still works (just deprecated)
3. Manual runs can keep the app updated while debugging

---

## Success Criteria

- [ ] GitHub Actions workflow completes successfully for 5 consecutive days
- [ ] New images appear in the gallery daily
- [ ] No API errors in `error_log.txt`
- [ ] App loads correctly on ShinyApps.io with new content

---

## Decisions Made

1. **OpenAI API key** - Will create new key (old one expired)
2. **ShinyApps.io credentials** - Will generate new tokens
3. **Date handling** - Keep `today()-1` as it handles timezone differences correctly
4. **Old content** - Delete all 2023 images and prompts to start fresh
5. **Image storage** - Start with GitHub, migrate to Cloudflare R2 after app is running

---

## Cost Estimate

| Item | Monthly Cost |
|------|--------------|
| OpenAI API (30 prompts + 30 images) | ~$1-2 |
| ShinyApps.io Starter | Free |
| GitHub Actions | Free |
| **Total** | **~$1-2/month** |

*Note: DALL-E 3 at 1024x1024 standard quality is $0.04 per image = $1.20/month for daily images. GPT-4o-mini is negligible at ~$0.01/month for this usage.*
