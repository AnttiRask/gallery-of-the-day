# Backfill script for generating prompts and images for past dates
# Usage: Rscript R/backfill.R 2026-01-01 2026-01-24
#
# This script will:
# 1. For each date in the range, check if prompt exists in Turso
# 2. If not, generate prompt using GPT-4o-mini and save to Turso
# 3. Check if image exists in R2
# 4. If not, generate image using GPT Image 1.5 and upload to R2

# Get credentials from environment variables (GitHub Actions) or secret.R (local)
OPENAI_API_KEY <- Sys.getenv("OPENAI_API_KEY")
if (OPENAI_API_KEY == "") {
    source("secret.R")
}

# Get R2 credentials - check env vars first, fall back to secret.R (already sourced above)
if (Sys.getenv("R2_ACCOUNT_ID") != "") {
    R2_ACCOUNT_ID        <- Sys.getenv("R2_ACCOUNT_ID")
    R2_ACCESS_KEY_ID     <- Sys.getenv("R2_ACCESS_KEY_ID")
    R2_SECRET_ACCESS_KEY <- Sys.getenv("R2_SECRET_ACCESS_KEY")
    R2_BUCKET_NAME       <- Sys.getenv("R2_BUCKET_NAME")
}
# Otherwise R2 credentials come from secret.R which was already sourced

# Load Turso helper functions
source("R/turso.R")

# Load packages
library(aws.s3)
library(curl)
library(dplyr)
library(httr2)
library(jsonlite)
library(lubridate)
library(purrr)
library(stringr)

# Parse command line arguments
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
    stop("Usage: Rscript R/backfill.R START_DATE END_DATE\n  Example: Rscript R/backfill.R 2026-01-01 2026-01-24")
}

start_date <- as.Date(args[1])
end_date   <- as.Date(args[2])

cat("Backfilling from", as.character(start_date), "to", as.character(end_date), "\n\n")

# R2 endpoint
r2_endpoint <- str_glue("{R2_ACCOUNT_ID}.r2.cloudflarestorage.com")

# Function to generate prompt for a specific date
generate_prompt <- function(target_date) {
    date_str <- format(target_date, "%B %d")

    prompt <- str_glue("Could you provide a brief description of a significant historical event that happened on {date_str} in history? Please include key visual details such as the main figures involved, their clothing, the setting, and any notable objects or symbols. Emphasize elements that would be impactful in a visual representation, and describe the emotional tone or atmosphere of the event.")

    body <- list(
        model       = "gpt-4o-mini",
        messages    = list(
            list(role = "system", content = "You are a historian providing vivid descriptions of historical events for artistic visualization."),
            list(role = "user", content = prompt)
        ),
        temperature = 0.7,
        max_tokens  = 4000
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

# Function to sanitize a prompt that was rejected by DALL-E
sanitize_prompt <- function(original_prompt) {
    cat("  Sanitizing prompt for DALL-E...\n")
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

# Function to get an alternative event for a date when the original is too problematic
get_alternative_event <- function(target_date) {
    date_str <- format(target_date, "%B %d")
    cat("  Requesting alternative event for", date_str, "...\n")

    body <- list(
        model       = "gpt-4o-mini",
        messages    = list(
            list(role = "system", content = "You are a historian who specializes in finding positive, uplifting historical events suitable for artistic visualization."),
            list(role = "user", content = str_glue("I need a DIFFERENT historical event for {date_str} that is suitable for AI image generation. Please choose an event that is:
- Peaceful, celebratory, or scientifically/culturally significant
- NOT related to wars, conflicts, tragedies, or controversial topics
- Visually interesting (art, science discoveries, cultural celebrations, sports achievements, space exploration, etc.)

Provide a vivid visual description of this event including the setting, people involved, their clothing, and the atmosphere. Focus on elements that would make a beautiful, uplifting image."))
        ),
        temperature = 0.9,
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

# Function to generate image for a prompt
# Returns NULL if DALL-E rejects the prompt (content policy)
generate_image <- function(prompt_text) {
    body <- list(
        model   = "gpt-image-1.5",
        prompt  = prompt_text,
        n       = 1,
        size    = "1024x1024",
        quality = "hd"
    )

    tryCatch({
        response <- request("https://api.openai.com/v1/images/generations") %>%
            req_headers(Authorization = str_glue("Bearer {OPENAI_API_KEY}")) %>%
            req_body_json(body) %>%
            req_retry(max_tries = 3, backoff = ~ 60) %>%
            req_perform()

        response %>%
            resp_body_json() %>%
            pluck("data", 1, "url")
    }, error = function(e) {
        cat("  DALL-E error:", conditionMessage(e), "\n")
        NULL
    })
}

# Try to generate image, sanitize and retry if rejected, then try alternative event
generate_image_with_retry <- function(prompt_text, target_date) {
    # First attempt
    image_url <- generate_image(prompt_text)

    if (!is.null(image_url)) {
        return(image_url)
    }

    # If rejected, sanitize and retry
    cat("  Retrying with sanitized prompt...\n")
    sanitized <- sanitize_prompt(prompt_text)
    Sys.sleep(2)

    image_url <- generate_image(sanitized)

    if (!is.null(image_url)) {
        return(image_url)
    }

    # If still rejected, try completely different event
    cat("  Retrying with alternative event...\n")
    alternative <- get_alternative_event(target_date)
    Sys.sleep(2)

    generate_image(alternative)
}

# Process each date
dates <- seq(start_date, end_date, by = "day")

for (target_date in dates) {
    target_date <- as.Date(target_date, origin = "1970-01-01")
    date_str <- as.character(target_date)
    object_key <- str_glue("gallery-of-the-day-{date_str}.png")

    cat("=== Processing", date_str, "===\n")

    # Check if prompt exists
    existing <- turso_query(
        "SELECT text FROM prompts WHERE date = ?",
        list(date_str)
    )

    if (nrow(existing) > 0) {
        cat("  Prompt already exists\n")
        prompt_text <- existing$text[1]
    } else {
        cat("  Generating prompt...\n")
        prompt_text <- generate_prompt(target_date)

        turso_execute(
            "INSERT INTO prompts (text, date) VALUES (?, ?)",
            list(prompt_text, date_str)
        )
        cat("  Prompt saved to Turso\n")

        # Small delay to avoid rate limits
        Sys.sleep(1)
    }

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
    }, error = function(e) {
        FALSE
    })

    if (isTRUE(image_exists)) {
        cat("  Image already exists in R2\n")
    } else {
        cat("  Generating image with GPT Image 1.5...\n")
        image_url <- generate_image_with_retry(prompt_text, target_date)

        if (is.null(image_url)) {
            cat("  SKIPPING: DALL-E rejected this prompt (content policy)\n")
            next
        }

        # Download to temp file
        temp_file <- tempfile(fileext = ".png")
        curl_download(image_url, temp_file, mode = "wb")

        # Upload to R2
        cat("  Uploading to R2...\n")
        cat("    Bucket:", R2_BUCKET_NAME, "\n")
        cat("    Endpoint:", r2_endpoint, "\n")
        cat("    Object:", object_key, "\n")

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
            cat("  R2 upload error:", conditionMessage(e), "\n")
            FALSE
        })

        cat("    Put result:", as.character(put_result), "\n")
        unlink(temp_file)

        if (isTRUE(put_result)) {
            cat("  Image uploaded to R2\n")
        } else {
            cat("  WARNING: Failed to upload image to R2\n")
        }

        # Delay between DALL-E requests to avoid rate limits
        cat("  Waiting 5 seconds before next image...\n")
        Sys.sleep(5)
    }

    cat("\n")
}

cat("Backfill complete!\n")
