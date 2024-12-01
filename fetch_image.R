# Source the secret ----
source("secret.R")

# Load packages ----
library(conflicted)
    conflicts_prefer(dplyr::filter)
library(curl)
library(dplyr)
library(httr2)
library(jsonlite)
library(lubridate)
library(purrr)
library(readr)
library(stringr)

# Create the API POST request ----

## Insert the arguments ----

# Model
model   <- "dall-e-3"

# The text prompt
prompts <- read_csv("app/data/prompts.csv")
prompt  <- prompts %>%
    filter(date == max(date)) %>%
    pull(text)

# The number of images
n       <- 1

# Image size
size    <- "1024x1024"

# Image quality
quality <- "standard"

## Create the request ----

# The URL for this particular use case (see documentation for others)
url <- "https://api.openai.com/v1/images/generations"

# Gather the arguments as the body of the request
body    <- list(
    model   = model,
    prompt  = prompt,
    n       = n,
    size    = size,
    quality = quality
)

# For the request you need to replace the OPENAI_API_KEY with your own API key
# that you get after signing up: https://platform.openai.com/account/api-keys
# OPENAI_API_KEY <- Sys.getenv("OPENAI_API_KEY")

max_retries  <- 3
initial_wait <- 1  # Wait time in seconds

make_request <- function(attempt) {
    response <- request(url) %>%
        req_headers(Authorization = str_glue("Bearer {OPENAI_API_KEY}")) %>%
        req_body_json(body) %>%
        req_perform()
    
    if (is.null(response)) {
        cat("Error: Response is NULL\n")
        return(NULL)
    }
    
    if (response$status_code == 429) {
        Sys.sleep(initial_wait * attempt)
        return(NULL)
    } else {
        return(response)
    }
}

safe_request <- possibly(
    make_request,
    otherwise = NULL
)

responses    <- map(1:max_retries, safe_request) %>%
    compact() %>%
    first()

# Check if we got a successful response
if (is.null(responses) || responses$status_code != 200) {
    log_message <- str_c(
        now(),
        " - Request failed after ",
        max_retries,
        " retries. Status: ",
        responses$status_code,
        " -",
        responses$message
    )
    
    # Example of logging
    write(log_message, file = "error_log.txt", append = TRUE)
}

# request <- request(url) %>%
#     req_headers(Authorization = str_glue("Bearer {OPENAI_API_KEY}")) %>%
#     req_body_json(body) %>%
#     req_perform()

# Save the image URL ----
url_img <- responses %>%
    resp_body_json() %>%
    pluck("data") %>%
    unlist() %>%
    pluck("url")

# Download the image ----

# Create the destination file name
destfile <- str_glue("app/img/gallery-of-the-day-{today() - 1}.png")

# Download the file at the URLand save it to 'destfile'
curl_download(url_img, destfile, mode = "wb")
