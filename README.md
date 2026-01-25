# Gallery of the Day

AI-generated art gallery that creates a new image daily based on historical events.

**[View Live App](https://youcanbeapirate.shinyapps.io/gallery-of-the-day/)**

![Gallery of the Day](img/gallery-of-the-day-example.png)

## Features

- Daily AI-generated images inspired by historical events
- Uses GPT-4o-mini to research and describe significant events
- Creates images with DALL-E 3 based on those descriptions
- Fully automated via GitHub Actions
- Deployed to ShinyApps.io

## Tech Stack

| Component | Technology |
|-----------|------------|
| Language | R |
| Web Framework | Shiny |
| AI Models | GPT-4o-mini, DALL-E 3 |
| Automation | GitHub Actions |
| Hosting | ShinyApps.io |
| Package Management | renv |

## Project Structure

```
gallery-of-the-day/
├── R/                              # Automation scripts
│   ├── create_prompt.R             # Generates historical event descriptions
│   ├── fetch_image.R               # Creates and downloads DALL-E images
│   └── deploy_app.R                # Deploys to ShinyApps.io
├── app/                            # Shiny application
│   ├── data/
│   │   └── prompts.csv             # Historical event descriptions
│   ├── img/                        # Generated images
│   ├── www/
│   │   ├── functions.R             # Helper functions
│   │   └── styles.css              # Custom styling
│   ├── ui.R                        # User interface
│   ├── server.R                    # Server logic
│   └── run.R                       # App entry point
├── .github/workflows/
│   └── r_scripts_daily.yml         # Daily automation workflow
├── renv.lock                       # Package dependencies
└── ROADMAP.md                      # Future improvements
```

## How It Works

### 1. Prompt Generation (`create_prompt.R`)

Uses GPT-4o-mini to research a significant historical event for today's date:

> "Could you provide a brief description of a significant historical event that happened on {date} in history? Please include key visual details such as the main figures involved, their clothing, the setting, and any notable objects or symbols."

### 2. Image Generation (`fetch_image.R`)

Sends the historical description to DALL-E 3 to generate a unique artwork. The image is saved with the date in the filename for easy lookup.

### 3. App Deployment (`deploy_app.R`)

Deploys the Shiny app to ShinyApps.io with the new content.

### 4. Automation

GitHub Actions runs daily at 4 AM UTC:
1. Generate prompt for today
2. Create and fetch image
3. Deploy updated app
4. Commit new files to repository

## Local Development

### Prerequisites

- R (>= 4.0)
- RStudio (recommended)
- OpenAI API key

### Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/youcanbeapirate/gallery-of-the-day.git
   cd gallery-of-the-day
   ```

2. Install dependencies:
   ```r
   renv::restore()
   ```

3. Create `secret.R` with your credentials:
   ```r
   OPENAI_API_KEY <- "your-openai-api-key"
   SHINY_APPS_NAME <- "your-shinyapps-name"
   SHINY_APPS_TOKEN <- "your-shinyapps-token"
   SHINY_APPS_SECRET <- "your-shinyapps-secret"
   ```

4. Run the scripts:
   ```r
   source("R/create_prompt.R")
   source("R/fetch_image.R")
   ```

5. Run the Shiny app locally:
   ```r
   shiny::runApp("app")
   ```

## GitHub Actions Setup

Add these secrets to your repository:

| Secret | Description |
|--------|-------------|
| `OPENAI_API_KEY` | Your OpenAI API key |
| `SHINY_APPS_NAME` | ShinyApps.io account name |
| `SHINY_APPS_TOKEN` | ShinyApps.io token |
| `SHINY_APPS_SECRET` | ShinyApps.io secret |

## Roadmap

See [ROADMAP.md](ROADMAP.md) for planned improvements including:
- External image storage (Cloudflare R2)
- Database for prompt storage
- Shiny app UI makeover
- GitHub Pages documentation

## License

MIT License - see [LICENSE](LICENSE) for details.
