# Roadmap

Future improvements for Gallery of the Day.

## Completed

- [x] Migrate from deprecated GPT-3.5-turbo-instruct to GPT-4o-mini
- [x] Fix GitHub Actions timeout issues (switched to Ubuntu runner)
- [x] Add retry logic for DALL-E API calls
- [x] Add idempotent checks (skip if prompt/image already exists)
- [x] Organize R scripts into `R/` folder
- [x] Update README to modern format

## Planned

### External Image Storage

Move images from GitHub to Cloudflare R2 storage.

**Why:**
- GitHub isn't designed for storing binary files
- R2 is cost-effective (free tier: 10GB storage, 1M requests/month)
- Better performance for image delivery

**Tasks:**
- Set up Cloudflare R2 bucket
- Add R2 credentials to GitHub secrets
- Update `fetch_image.R` to upload to R2
- Update Shiny app to fetch images from R2 URL
- Migrate existing images

### Lightweight Database

Replace CSV storage with a proper database.

**Options to consider:**
- SQLite (simple, file-based)
- Turso (SQLite on the edge)
- Supabase (PostgreSQL, generous free tier)

**Benefits:**
- Better query performance
- Proper date indexing
- Easier to add metadata fields

### Shiny App Makeover

Modernize the UI/UX of the Shiny app.

**Ideas:**
- Use bslib for modern Bootstrap 5 styling
- Add "About" and "About Me" tabs
- Improve mobile responsiveness
- Add image loading states
- Consider dark mode support

### GitHub Pages

Add a GitHub Pages site for documentation.

**Could include:**
- Project documentation
- Image archive/gallery view
- Blog posts about interesting historical events
- Technical write-ups

## Future Ideas

- Prompt tweaking for more diverse historical events (not just wars and politics)
- Social media sharing buttons
- RSS feed for new images
- Multiple art styles option
- Community voting on favorite images
