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

# Load Turso helper functions and the shared settings and OpenAI helpers
source("R/turso.R")
source("R/config.R")
source("R/openai.R")

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

# The text prompt for this date (from Turso database) ----
prompt_result <- turso_query(
    "SELECT text FROM prompts WHERE date = ?",
    list(as.character(image_date))
)

if (nrow(prompt_result) == 0 || is.na(prompt_result$text[1]) || prompt_result$text[1] == "") {
    stop("There is no prompt for ", image_date, " in Turso. Run R/create_prompt.R first.")
}

prompt <- prompt_result$text[1]

cat("Prompt length:", nchar(prompt), "characters\n")

# Create the image (the model and its settings live in R/config.R). If the
# safety system blocks the prompt, a rewritten and then a different event is tried.
cat("Making", openai_image_model, "request...\n")

result <- generate_image_with_fallbacks(prompt, image_date)

# Update the prompt in Turso if we had to use a different one
if (result$changed) {
    cat("Updating prompt in Turso with the successful version...\n")
    turso_execute(
        "UPDATE prompts SET text = ? WHERE date = ?",
        list(result$caption, as.character(image_date))
    )
}

# Save the image to a temp file
temp_file <- tempfile(fileext = ".png")
writeBin(result$image, temp_file)
cat("Image saved to temp file\n")

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
    TRUE  # put_object returns a structure on success, so explicitly return TRUE
}, error = function(e) {
    cat("R2 upload error:", conditionMessage(e), "\n")
    FALSE
})

if (put_result) {
    cat("Image uploaded to R2:", object_key, "\n")
} else {
    stop("Failed to upload image to R2")
}

# Clean up temp file
unlink(temp_file)

cat("Done!\n")
