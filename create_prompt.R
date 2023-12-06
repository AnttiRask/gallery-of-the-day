# # Source the secret ----
# source("secret.R")

# Load packages ----
library(dplyr)
library(httr2)
library(lubridate)
library(purrr)
library(readr)
library(stringr)

# Create the API POST request ----

## Insert the arguments ----

# The text prompt. Explore!
date        <- today() %>% format("%B %d")
prompt      <- str_glue("Could you provide a brief description of a significant historical event that happened on {date} in history? Please include key visual details such as the main figures involved, their clothing, the setting, and any notable objects or symbols. Emphasize elements that would be impactful in a visual representation, and describe the emotional tone or atmosphere of the event.")

# The number of texts
n           <- 1

# Max number of tokens used
max_tokens  <- 4000

# Temperature (between 0 and 1 where 1 is most risky)
temperature <- 0

# Model used
model       <- "gpt-3.5-turbo-instruct"

## Create the request ----

# The URL for this particular use case (see documentation for others)
url         <- "https://api.openai.com/v1/completions"

# Gather the arguments as the body of the request
body    <- list(
    model       = model,
    prompt      = prompt,
    n           = n,
    temperature = temperature,
    max_tokens  = max_tokens
)

# For the request You need to replace the OPENAI_API_KEY with your own API key
# that you get after signing up: https://platform.openai.com/account/api-keys
request <- request(url) %>%
    req_headers(Authorization = str_glue("Bearer {Sys.getenv(OPENAI_API_KEY)}")) %>%
    req_body_json(body) %>%
    req_perform()

# Check the request was successful (status code should be 200) ----
request$status_code

# Let's take a look at the content ----
request %>%
    resp_body_json() %>% 
    glimpse()

# Save the prompt ----
prompts_new <- request %>%
    resp_body_json() %>%
    pluck("choices") %>%
    unlist() %>%
    pluck("text") %>%
    as_tibble() %>%
    rename(text = value) %>%
    mutate(
        text = str_remove_all(text, "\\\n"),
        date = today()
    ) 

# Save the text output in a txt file ----

# Define the file path
file_path <- "data/prompts.csv"

# Check if the file exists
if (file.exists(file_path)) {
    # Read existing data
    prompts_existing <- read_csv(file_path)

    # Combine the existing and new data
    prompts_combined <- bind_rows(prompts_existing, prompts_new)

    # Write the combined data back to the CSV
    write_csv(prompts_combined, file_path)

} else {
    # Write the new data to a new CSV file
    write_csv(prompts_new, file_path)
}
