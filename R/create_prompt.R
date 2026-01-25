# Get API key from environment variable (GitHub Actions) or secret.R (local)
OPENAI_API_KEY <- Sys.getenv("OPENAI_API_KEY")
if (OPENAI_API_KEY == "") {
    source("secret.R")
}

# Load Turso helper functions
source("R/turso.R")

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

# Create the API POST request ----

## Insert the arguments ----

# The text prompt. Explore!
date        <- today() %>% format("%B %d")
prompt      <- str_glue("Could you provide a brief description of a significant historical event that happened on {date} in history? Please include key visual details such as the main figures involved, their clothing, the setting, and any notable objects or symbols. Emphasize elements that would be impactful in a visual representation, and describe the emotional tone or atmosphere of the event.")

# Max number of tokens used
max_tokens  <- 4000

# Temperature (between 0 and 1 where 1 is most creative)
temperature <- 0.7

# Model used (gpt-4o-mini is cheaper and better than gpt-3.5-turbo)
model       <- "gpt-4o-mini"

## Create the request ----

# The URL for Chat Completions API
url         <- "https://api.openai.com/v1/chat/completions"

# System message to set the AI's role
system_message <- "You are a historian providing vivid descriptions of historical events for artistic visualization."

# Gather the arguments as the body of the request (Chat Completions format)
body    <- list(
    model       = model,
    messages    = list(
        list(role = "system", content = system_message),
        list(role = "user", content = prompt)
    ),
    temperature = temperature,
    max_tokens  = max_tokens
)

cat("Making GPT-4o-mini request...\n")

response <- request(url) %>%
    req_headers(Authorization = str_glue("Bearer {OPENAI_API_KEY}")) %>%
    req_body_json(body) %>%
    req_perform()

# Check the request was successful (status code should be 200) ----
cat("Response status:", response$status_code, "\n")

# Extract the prompt text ----
prompt_text <- response %>%
    resp_body_json() %>%
    pluck("choices", 1, "message", "content") %>%
    str_remove_all("\\\n")  # Remove escaped newlines

cat("Generated prompt length:", nchar(prompt_text), "characters\n")

# Save to Turso database ----
cat("Saving to Turso database...\n")

turso_execute(
    "INSERT INTO prompts (text, date) VALUES (?, ?)",
    list(prompt_text, today_date)
)

cat("Prompt saved for", today_date, "\n")
