# Backfill prompt + image for a single past date.
# Usage: Rscript R/backfill_date.R YYYY-MM-DD
#
# Mirrors create_prompt.R + fetch_image.R but parameterized by date so a gap in
# the daily run can be filled in. Inserts the prompt into Turso and uploads the
# image to R2 under gallery-of-the-day-YYYY-MM-DD.png. Skips work that's already
# done so it's safe to re-run.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1 || !grepl("^\\d{4}-\\d{2}-\\d{2}$", args[1])) {
    stop("Usage: Rscript R/backfill_date.R YYYY-MM-DD")
}
target_date <- as.Date(args[1])
target_date_str <- as.character(target_date)

OPENAI_API_KEY <- Sys.getenv("OPENAI_API_KEY")
if (OPENAI_API_KEY == "") {
    source("secret.R")
}

R2_ACCOUNT_ID        <- Sys.getenv("R2_ACCOUNT_ID")
R2_ACCESS_KEY_ID     <- Sys.getenv("R2_ACCESS_KEY_ID")
R2_SECRET_ACCESS_KEY <- Sys.getenv("R2_SECRET_ACCESS_KEY")
R2_BUCKET_NAME       <- Sys.getenv("R2_BUCKET_NAME")

source("R/turso.R")
source("R/config.R")
source("R/wikipedia.R")
source("R/openai.R")

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

# ---- Step 1: ensure a prompt exists in Turso for target_date ----

existing <- turso_query(
    "SELECT text FROM prompts WHERE date = ?",
    list(target_date_str)
)

if (nrow(existing) > 0 && !is.na(existing$text[1]) && nchar(existing$text[1]) > 0) {
    cat("Prompt for", target_date_str, "already exists in Turso. Reusing it.\n")
    prompt_text <- existing$text[1]
} else {
    cat("Asking", openai_text_model, "for an event on", date_label(target_date), "...\n")

    event <- generate_event(target_date)
    prompt_text <- event$caption

    cat("Event:", event$year, "-", event$event, "\n")
    cat("Generated prompt length:", nchar(prompt_text), "characters\n")

    if (nrow(existing) > 0) {
        turso_execute(
            "UPDATE prompts SET text = ? WHERE date = ?",
            list(prompt_text, target_date_str)
        )
    } else {
        turso_execute(
            "INSERT INTO prompts (text, date) VALUES (?, ?)",
            list(prompt_text, target_date_str)
        )
    }
    cat("Prompt saved for", target_date_str, "\n")
}

# ---- Step 2: ensure an image exists in R2 for target_date ----

object_key <- str_glue("gallery-of-the-day-{target_date_str}.png")
r2_endpoint <- str_glue("{R2_ACCOUNT_ID}.r2.cloudflarestorage.com")

image_exists <- tryCatch({
    head_object(
        object   = object_key,
        bucket   = R2_BUCKET_NAME,
        key      = R2_ACCESS_KEY_ID,
        secret   = R2_SECRET_ACCESS_KEY,
        base_url = r2_endpoint,
        region   = ""
    )
}, error = function(e) FALSE)

if (isTRUE(image_exists)) {
    cat("Image for", target_date_str, "already in R2. Done.\n")
    quit(save = "no", status = 0)
}

# The model and its settings live in R/config.R. If the safety system blocks the
# prompt, a rewritten and then a different event is tried.
cat("Making", openai_image_model, "request for", target_date_str, "...\n")

result <- generate_image_with_fallbacks(prompt_text, target_date)

if (result$changed) {
    cat("Updating Turso prompt to the version that succeeded.\n")
    turso_execute(
        "UPDATE prompts SET text = ? WHERE date = ?",
        list(result$caption, target_date_str)
    )
}

temp_file <- tempfile(fileext = ".png")
writeBin(result$image, temp_file)
cat("Image saved, uploading to R2 as", object_key, "\n")

put_ok <- tryCatch({
    put_object(
        file     = temp_file,
        object   = object_key,
        bucket   = R2_BUCKET_NAME,
        key      = R2_ACCESS_KEY_ID,
        secret   = R2_SECRET_ACCESS_KEY,
        base_url = r2_endpoint,
        region   = ""
    )
    TRUE
}, error = function(e) {
    cat("R2 upload error:", conditionMessage(e), "\n"); FALSE
})

unlink(temp_file)

if (!put_ok) stop("Failed to upload image to R2")
cat("Done backfilling", target_date_str, "\n")
