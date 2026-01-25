# Get API key from environment variable (GitHub Actions) or secret.R (local)
OPENAI_API_KEY <- Sys.getenv("OPENAI_API_KEY")
if (OPENAI_API_KEY == "") {
    source("secret.R")
}

# Get R2 credentials from environment variables or secret.R (already sourced above)
R2_ACCOUNT_ID        <- Sys.getenv("R2_ACCOUNT_ID")
R2_ACCESS_KEY_ID     <- Sys.getenv("R2_ACCESS_KEY_ID")
R2_SECRET_ACCESS_KEY <- Sys.getenv("R2_SECRET_ACCESS_KEY")
R2_BUCKET_NAME       <- Sys.getenv("R2_BUCKET_NAME")

# Load packages ----
library(conflicted)
    conflicts_prefer(dplyr::filter)
library(aws.s3)
library(curl)
library(dplyr)
library(httr2)
library(jsonlite)
library(lubridate)
library(purrr)
library(readr)
library(stringr)

# Check if today's image already exists in R2 ----
image_date <- today()
object_key <- str_glue("gallery-of-the-day-{image_date}.png")
r2_endpoint <- str_glue("{R2_ACCOUNT_ID}.r2.cloudflarestorage.com")

# Check if image exists in R2
image_exists <- tryCatch({
    head_object(
        object   = object_key,
        bucket   = R2_BUCKET_NAME,
        key      = R2_ACCESS_KEY_ID,
        secret   = R2_SECRET_ACCESS_KEY,
        base_url = r2_endpoint,
        region   = ""
    )
    TRUE
}, error = function(e) {
    FALSE
})

if (image_exists) {
    cat("Image for", as.character(image_date), "already exists in R2. Skipping.\n")
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

# Download and upload to R2 ----

# Download to temp file first
temp_file <- tempfile(fileext = ".png")
curl_download(url_img, temp_file, mode = "wb")
cat("Image downloaded to temp file\n")

# Upload to Cloudflare R2
cat("Uploading to R2...\n")

put_result <- put_object(
    file     = temp_file,
    object   = object_key,
    bucket   = R2_BUCKET_NAME,
    key      = R2_ACCESS_KEY_ID,
    secret   = R2_SECRET_ACCESS_KEY,
    base_url = r2_endpoint,
    region   = ""
)

if (put_result) {
    cat("Image uploaded to R2:", object_key, "\n")
} else {
    stop("Failed to upload image to R2")
}

# Clean up temp file
unlink(temp_file)

cat("Done!\n")
