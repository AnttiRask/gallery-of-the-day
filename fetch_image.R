# Get API key from environment variable (GitHub Actions) or secret.R (local)
OPENAI_API_KEY <- Sys.getenv("OPENAI_API_KEY")
if (OPENAI_API_KEY == "") {
    source("secret.R")
}

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

# Check if today's image already exists ----
image_date <- today()
image_path <- str_glue("app/img/gallery-of-the-day-{image_date}.png")
if (file.exists(image_path)) {
    cat("Image for", as.character(image_date), "already exists. Skipping.\n")
    quit(save = "no", status = 0)
}

# Create the API POST request ----

## Insert the arguments ----

# Model
model   <- "dall-e-3"

# The text prompt
prompts <- read_csv("app/data/prompts.csv")
prompt  <- prompts %>%
    filter(date == max(date)) %>%
    pull(text)

cat("Prompt length:", nchar(prompt), "characters\n")

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

# Make the request with retry logic
cat("Making DALL-E 3 request...\n")

response <- tryCatch({
    request(url) %>%
        req_headers(Authorization = str_glue("Bearer {OPENAI_API_KEY}")) %>%
        req_body_json(body) %>%
        req_retry(max_tries = 3, backoff = ~ 60) %>%
        req_perform()
}, error = function(e) {
    cat("Error making request:", conditionMessage(e), "\n")

    # Log the error
    log_message <- str_c(
        now(), " - DALL-E request failed: ", conditionMessage(e)
    )
    write(log_message, file = "error_log.txt", append = TRUE)

    stop(e)
})

cat("Response status:", response$status_code, "\n")

# Check if we got a successful response
if (response$status_code != 200) {
    error_body <- resp_body_json(response)
    cat("Error response:", toJSON(error_body, auto_unbox = TRUE), "\n")

    log_message <- str_c(
        now(), " - Request failed with status ", response$status_code
    )
    write(log_message, file = "error_log.txt", append = TRUE)

    stop("DALL-E API returned error status: ", response$status_code)
}

# Save the image URL ----
url_img <- response %>%
    resp_body_json() %>%
    pluck("data", 1, "url")

cat("Got image URL, downloading...\n")

# Download the image ----

# Ensure the img directory exists (Git doesn't track empty directories)
if (!dir.exists("app/img")) {
    dir.create("app/img", recursive = TRUE)
}

# Create the destination file name (must match the date in prompts.csv)
destfile <- str_glue("app/img/gallery-of-the-day-{today()}.png")

# Download the file at the URL and save it to 'destfile'
curl_download(url_img, destfile, mode = "wb")

cat("Image saved to:", destfile, "\n")
