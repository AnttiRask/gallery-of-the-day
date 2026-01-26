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

# Load Turso helper functions
source("R/turso.R")

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
library(stringr)

# Check if today's image already exists in R2 ----
image_date <- today()
object_key <- str_glue("gallery-of-the-day-{image_date}.png")
r2_endpoint <- str_glue("{R2_ACCOUNT_ID}.r2.cloudflarestorage.com")

# Check if image exists in R2
# head_object returns TRUE if exists, FALSE if 404
image_exists <- tryCatch({
    head_object(
        object   = object_key,
        bucket   = R2_BUCKET_NAME,
        key      = R2_ACCESS_KEY_ID,
        secret   = R2_SECRET_ACCESS_KEY,
        base_url = r2_endpoint,
        region   = ""
    )
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

# The text prompt (from Turso database)
prompt_result <- turso_query("SELECT text FROM prompts ORDER BY date DESC LIMIT 1")
prompt <- prompt_result$text[1]

cat("Prompt length:", nchar(prompt), "characters\n")

# Function to sanitize a prompt that was rejected by DALL-E
sanitize_prompt <- function(original_prompt) {
    cat("Sanitizing prompt for DALL-E...\n")
    body <- list(
        model       = "gpt-4o-mini",
        messages    = list(
            list(role = "system", content = "You are an expert at rewriting historical event descriptions to be suitable for AI image generation. Rewrite the prompt to focus on peaceful, artistic, and symbolic elements while avoiding any violence, conflict, weapons, or controversial imagery. Keep the historical context but make it safe for image generation."),
            list(role = "user", content = str_glue("Please rewrite this historical event description to be suitable for DALL-E image generation (avoid violence, weapons, conflict):\n\n{original_prompt}"))
        ),
        temperature = 0.7,
        max_tokens  = 2000
    )

    response <- request("https://api.openai.com/v1/chat/completions") %>%
        req_headers(Authorization = str_glue("Bearer {OPENAI_API_KEY}")) %>%
        req_body_json(body) %>%
        req_perform()

    response %>%
        resp_body_json() %>%
        pluck("choices", 1, "message", "content") %>%
        str_remove_all("\\\n")
}

# The number of images
n       <- 1

# Image size
size    <- "1024x1024"

# Image quality
quality <- "standard"

## Create the request ----

# The URL for this particular use case (see documentation for others)
url <- "https://api.openai.com/v1/images/generations"

# Function to make DALL-E request
make_dalle_request <- function(prompt_text) {
    body <- list(
        model   = model,
        prompt  = prompt_text,
        n       = n,
        size    = size,
        quality = quality
    )

    request(url) %>%
        req_headers(Authorization = str_glue("Bearer {OPENAI_API_KEY}")) %>%
        req_body_json(body) %>%
        req_retry(max_tries = 3, backoff = ~ 60) %>%
        req_perform()
}

# Make the request with retry logic
cat("Making DALL-E 3 request...\n")

response <- tryCatch({
    make_dalle_request(prompt)
}, error = function(e) {
    cat("DALL-E error (will retry with sanitized prompt):", conditionMessage(e), "\n")
    NULL
})

# If first attempt failed, try with sanitized prompt
if (is.null(response)) {
    sanitized_prompt <- sanitize_prompt(prompt)
    cat("Retrying with sanitized prompt...\n")
    cat("Sanitized prompt length:", nchar(sanitized_prompt), "characters\n")

    response <- tryCatch({
        make_dalle_request(sanitized_prompt)
    }, error = function(e) {
        cat("Error making request:", conditionMessage(e), "\n")

        log_message <- str_c(
            now(), " - DALL-E request failed even after sanitization: ", conditionMessage(e)
        )
        write(log_message, file = "error_log.txt", append = TRUE)

        stop(e)
    })
}

cat("Response status:", response$status_code, "\n")

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
cat("Bucket:", R2_BUCKET_NAME, "\n")
cat("Object key:", object_key, "\n")
cat("Endpoint:", r2_endpoint, "\n")

put_result <- tryCatch({
    put_object(
        file     = temp_file,
        object   = object_key,
        bucket   = R2_BUCKET_NAME,
        key      = R2_ACCESS_KEY_ID,
        secret   = R2_SECRET_ACCESS_KEY,
        base_url = r2_endpoint,
        region   = ""
    )
}, error = function(e) {
    cat("R2 upload error:", conditionMessage(e), "\n")
    FALSE
})

cat("Put result:", as.character(put_result), "\n")

if (isTRUE(put_result)) {
    cat("Image uploaded to R2:", object_key, "\n")
} else {
    stop("Failed to upload image to R2")
}

# Clean up temp file
unlink(temp_file)

cat("Done!\n")
