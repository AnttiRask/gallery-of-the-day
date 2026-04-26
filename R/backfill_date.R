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
    cat("Generating prompt for", target_date_str, "...\n")
    date_label <- format(target_date, "%B %d")
    user_prompt <- str_glue("You must provide a vivid visual description of a historical event from {date_label} that is suitable for AI image generation.

REQUIREMENTS - You MUST choose from these categories ONLY:
1. Scientific discoveries or technological breakthroughs
2. Cultural celebrations, festivals, or traditions
3. Artistic achievements (music premiers, art unveilings, literary milestones)
4. Sports achievements or inaugural events
5. Space exploration milestones
6. Peaceful diplomatic achievements or treaty signings
7. Architectural completions or inaugurations
8. Conservation or humanitarian milestones

STRICT PROHIBITIONS - NEVER describe:
- Wars, battles, military conflicts, or violence of any kind
- Weapons, armor, or military equipment
- Tragedies, disasters, assassinations, or deaths
- Political controversies or protests

VISUAL DESCRIPTION FORMAT:
Describe the scene with vivid details: the setting, the people involved (their clothing, expressions, poses), the atmosphere (lighting, weather, mood), and significant objects or symbols. Focus on creating a visually compelling, uplifting image that celebrates human achievement or cultural heritage.

You MUST select an event from exactly {date_label}. If no event perfectly matches all categories above, choose the most positive and visually compelling event that occurred on this exact date in any year throughout history.")

    system_message <- "You are a cultural historian specializing in positive human achievements, scientific discoveries, and artistic milestones. You NEVER describe violence, conflict, or tragedy. Your role is to find the most visually compelling, uplifting historical moments suitable for beautiful AI-generated artwork."

    body <- list(
        model = "gpt-4o-mini",
        messages = list(
            list(role = "system", content = system_message),
            list(role = "user", content = user_prompt)
        ),
        temperature = 0.7,
        max_tokens = 4000
    )

    response <- request("https://api.openai.com/v1/chat/completions") %>%
        req_headers(Authorization = str_glue("Bearer {OPENAI_API_KEY}")) %>%
        req_body_json(body) %>%
        req_perform()

    prompt_text <- response %>%
        resp_body_json() %>%
        pluck("choices", 1, "message", "content") %>%
        str_remove_all("\\\n")

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

sanitize_prompt <- function(original_prompt) {
    cat("Sanitizing prompt for DALL-E...\n")
    body <- list(
        model = "gpt-4o-mini",
        messages = list(
            list(role = "system", content = "You are an expert at rewriting historical event descriptions to be suitable for AI image generation. Rewrite the prompt to focus on peaceful, artistic, and symbolic elements while avoiding any violence, conflict, weapons, or controversial imagery. Keep the historical context but make it safe for image generation."),
            list(role = "user", content = str_glue("Please rewrite this historical event description to be suitable for DALL-E image generation (avoid violence, weapons, conflict):\n\n{original_prompt}"))
        ),
        temperature = 0.7,
        max_tokens = 2000
    )
    request("https://api.openai.com/v1/chat/completions") %>%
        req_headers(Authorization = str_glue("Bearer {OPENAI_API_KEY}")) %>%
        req_body_json(body) %>%
        req_perform() %>%
        resp_body_json() %>%
        pluck("choices", 1, "message", "content") %>%
        str_remove_all("\\\n")
}

get_alternative_event <- function(d) {
    date_str <- format(d, "%B %d")
    cat("Requesting alternative event for", date_str, "...\n")
    body <- list(
        model = "gpt-4o-mini",
        messages = list(
            list(role = "system", content = "You are a historian who specializes in finding positive, uplifting historical events suitable for artistic visualization."),
            list(role = "user", content = str_glue("I need a DIFFERENT historical event for {date_str} that is suitable for AI image generation. Please choose an event that is:
- Peaceful, celebratory, or scientifically/culturally significant
- NOT related to wars, conflicts, tragedies, or controversial topics
- Visually interesting (art, science discoveries, cultural celebrations, sports achievements, space exploration, etc.)

Provide a vivid visual description of this event including the setting, people involved, their clothing, and the atmosphere. Focus on elements that would make a beautiful, uplifting image."))
        ),
        temperature = 0.9,
        max_tokens = 2000
    )
    request("https://api.openai.com/v1/chat/completions") %>%
        req_headers(Authorization = str_glue("Bearer {OPENAI_API_KEY}")) %>%
        req_body_json(body) %>%
        req_perform() %>%
        resp_body_json() %>%
        pluck("choices", 1, "message", "content") %>%
        str_remove_all("\\\n")
}

make_image_request <- function(p) {
    body <- list(
        model = "gpt-image-1.5",
        prompt = p,
        n = 1,
        size = "1024x1024",
        quality = "high"
    )
    request("https://api.openai.com/v1/images/generations") %>%
        req_headers(Authorization = str_glue("Bearer {OPENAI_API_KEY}")) %>%
        req_body_json(body) %>%
        req_retry(max_tries = 3, backoff = ~ 60) %>%
        req_perform()
}

cat("Making GPT Image 1.5 request for", target_date_str, "...\n")

used_prompt <- prompt_text
prompt_was_changed <- FALSE

response <- tryCatch(make_image_request(prompt_text), error = function(e) {
    cat("Image API error (will retry sanitized):", conditionMessage(e), "\n"); NULL
})

if (is.null(response)) {
    sanitized <- sanitize_prompt(prompt_text)
    cat("Retrying with sanitized prompt (", nchar(sanitized), "chars)\n")
    response <- tryCatch(make_image_request(sanitized), error = function(e) {
        cat("Sanitized prompt rejected:", conditionMessage(e), "\n"); NULL
    })
    if (!is.null(response)) {
        used_prompt <- sanitized
        prompt_was_changed <- TRUE
    }
}

if (is.null(response)) {
    alt <- get_alternative_event(target_date)
    cat("Retrying with alternative event (", nchar(alt), "chars)\n")
    response <- make_image_request(alt)
    used_prompt <- alt
    prompt_was_changed <- TRUE
}

if (prompt_was_changed) {
    cat("Updating Turso prompt to the version that succeeded.\n")
    turso_execute(
        "UPDATE prompts SET text = ? WHERE date = ?",
        list(used_prompt, target_date_str)
    )
}

cat("Response status:", response$status_code, "\n")

b64 <- response %>% resp_body_json() %>% pluck("data", 1, "b64_json")
temp_file <- tempfile(fileext = ".png")
writeBin(jsonlite::base64_dec(b64), temp_file)
cat("Image decoded, uploading to R2 as", object_key, "\n")

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
