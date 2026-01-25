# Get API key from environment variable (GitHub Actions) or secret.R (local)
OPENAI_API_KEY <- Sys.getenv("OPENAI_API_KEY")
if (OPENAI_API_KEY == "") {
    source("secret.R")
}

# Load packages ----
library(dplyr)
library(httr2)
library(jsonlite)
library(lubridate)
library(purrr)
library(readr)
library(stringr)

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

# For the request You need to replace the OPENAI_API_KEY with your own API key
# that you get after signing up: https://platform.openai.com/account/api-keys
# OPENAI_API_KEY <- Sys.getenv("OPENAI_API_KEY")

request <- request(url) %>%
    req_headers(Authorization = str_glue("Bearer {OPENAI_API_KEY}")) %>%
    req_body_json(body) %>%
    req_perform()

# Check the request was successful (status code should be 200) ----
request$status_code

# Let's take a look at the content ----
request %>%
    resp_body_json() %>% 
    glimpse()

# Save the prompt ----
# Chat Completions API returns content in choices[[1]]$message$content
prompts_new <- request %>%
    resp_body_json() %>%
    pluck("choices", 1, "message", "content") %>%
    as_tibble() %>%
    rename(text = value) %>%
    mutate(
        text = str_remove_all(text, "\\\n"),
        date = as.character(today())
    )

# Save the text output in a txt file ----

# Define the file path
file_path <- "app/data/prompts.csv"

# Check if the file exists and has data
if (file.exists(file_path)) {
    # Read existing data
    prompts_existing <- read_csv(file_path, col_types = cols(text = col_character(), date = col_character()))

    # Only combine if there's existing data
    if (nrow(prompts_existing) > 0) {
        prompts_combined <- bind_rows(prompts_existing, prompts_new)
    } else {
        prompts_combined <- prompts_new
    }

    # Write the combined data back to the CSV
    write_csv(prompts_combined, file_path)

} else {
    # Write the new data to a new CSV file
    write_csv(prompts_new, file_path)
}
