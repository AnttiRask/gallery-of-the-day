# Get API key from environment variable (GitHub Actions) or secret.R (local)
OPENAI_API_KEY <- Sys.getenv("OPENAI_API_KEY")
if (OPENAI_API_KEY == "") {
    source("secret.R")
}

# Load Turso helper functions and the shared settings and OpenAI helpers
source("R/turso.R")
source("R/config.R")
source("R/wikipedia.R")
source("R/openai.R")

# Load packages ----
library(dplyr)
library(httr2)
library(jsonlite)
library(lubridate)
library(purrr)
library(stringr)

# Check if today's prompt already exists in Turso ----
today_date <- as.character(today())
existing <- turso_query(
    "SELECT COUNT(*) as count FROM prompts WHERE date = ?",
    list(today_date)
)

if (as.integer(existing$count[1]) > 0) {
    cat("Prompt for", today_date, "already exists. Skipping.\n")
    quit(save = "no", status = 0)
}

# Ask the model for an event (the model and the prompt live in R/config.R) ----
cat("Asking", openai_text_model, "for an event on", date_label(today()), "...\n")

event <- generate_event(today())

cat("Event:", year_label(event$year), "-", event$event, "\n")
cat("Generated prompt length:", nchar(event$caption), "characters\n")

# Save to Turso database ----
cat("Saving to Turso database...\n")

turso_execute(
    "INSERT INTO prompts (text, date) VALUES (?, ?)",
    list(event$caption, today_date)
)

cat("Prompt saved for", today_date, "\n")
