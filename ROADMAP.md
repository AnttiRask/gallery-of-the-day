# Roadmap

Future improvements for Gallery of the Day.

## Completed

- [x] Migrate from deprecated GPT-3.5-turbo-instruct to GPT-4o-mini
- [x] Fix GitHub Actions timeout issues (switched to Ubuntu runner)
- [x] Add retry logic for DALL-E API calls
- [x] Add idempotent checks (skip if prompt/image already exists)
- [x] Organize R scripts into `R/` folder
- [x] Update README to modern format
- [x] Migrate image storage to Cloudflare R2

## Planned

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
