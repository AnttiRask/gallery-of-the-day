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
- [x] Migrate to Turso database (replaced CSV storage)
- [x] Add DALL-E prompt retry with sanitization and alternative events
- [x] Shiny App Makeover (bslib, Bootstrap 5, dark theme, mobile responsive)
- [x] GitHub Pages landing page
- [x] Google Cloud Run deployment with custom domain (galleryoftheday.youcanbeapirate.com)

## Future Ideas

- Prompt tweaking for more diverse historical events (not just wars and politics)
- Social media sharing buttons
- RSS feed for new images
- Multiple art styles option
- Community voting on favorite images
