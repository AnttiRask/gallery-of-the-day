# OpenAI calls shared by the daily scripts. Needs R/config.R, R/wikipedia.R, httr2, jsonlite.
#
# Every call fails with the API's own error message (not just "HTTP 400"), and
# only errors worth retrying are retried. A rejected request is never retried
# with the same input, so a bad key or an empty balance fails at once.

openai_key <- function() {
    key <- Sys.getenv("OPENAI_API_KEY")
    if (key == "" && exists("OPENAI_API_KEY", inherits = TRUE)) {
        key <- get("OPENAI_API_KEY", inherits = TRUE)
    }
    if (key == "") stop("OPENAI_API_KEY is not set")
    key
}

openai_error_code <- function(resp) {
    body <- tryCatch(httr2::resp_body_json(resp), error = function(e) NULL)
    body$error$code %||% NA_character_
}

openai_error_message <- function(resp) {
    body <- tryCatch(httr2::resp_body_json(resp), error = function(e) NULL)
    if (is.null(body$error)) return(NULL)
    paste0(body$error$message, " (", body$error$code %||% body$error$type, ")")
}

# Server errors and rate limits are worth retrying; an empty balance is not
is_transient_openai <- function(resp) {
    status <- httr2::resp_status(resp)
    status %in% c(500, 502, 503, 504) ||
        (status == 429 && !identical(openai_error_code(resp), "insufficient_quota"))
}

openai_perform <- function(url, body, max_tries = 5, backoff = getOption("openai.retry_backoff", 30)) {
    httr2::request(url) |>
        httr2::req_auth_bearer_token(openai_key()) |>
        httr2::req_body_json(body) |>
        httr2::req_timeout(600) |>
        httr2::req_retry(
            max_tries        = max_tries,
            retry_on_failure = TRUE,
            is_transient     = is_transient_openai,
            backoff          = \(i) backoff
        ) |>
        httr2::req_error(body = openai_error_message) |>
        httr2::req_perform()
}

# Text ----

# Ask the text model for a JSON object that matches `schema`
openai_text_json <- function(system, user, schema_name, schema) {
    body <- list(
        model                 = openai_text_model,
        messages              = list(
            list(role = "system", content = system),
            list(role = "user", content = user)
        ),
        reasoning_effort      = "none",
        max_completion_tokens = 4000,
        response_format       = list(
            type        = "json_schema",
            json_schema = list(name = schema_name, strict = TRUE, schema = schema)
        )
    )

    choice <- openai_perform("https://api.openai.com/v1/chat/completions", body) |>
        httr2::resp_body_json() |>
        purrr::pluck("choices", 1)

    if (!is.null(choice$message$refusal)) {
        stop("The text model refused: ", choice$message$refusal)
    }
    if (!identical(choice$finish_reason, "stop")) {
        stop("The text model did not finish (finish_reason: ", choice$finish_reason, ")")
    }

    tryCatch(
        jsonlite::fromJSON(choice$message$content),
        error = function(e) stop("The text model did not return valid JSON: ", conditionMessage(e))
    )
}

event_schema <- list(
    type                 = "object",
    properties           = list(
        choice  = list(type = "integer", description = "Number of the chosen event in the list"),
        caption = list(type = "string", description = "Plain-prose visual description of the scene")
    ),
    required             = list("choice", "caption"),
    additionalProperties = FALSE
)

caption_schema <- list(
    type                 = "object",
    properties           = list(
        caption = list(type = "string", description = "Plain-prose visual description of the scene")
    ),
    required             = I("caption"),
    additionalProperties = FALSE
)

# The caption is shown to visitors as it is, so refuse anything that is not plain prose
clean_caption <- function(caption) {
    if (!is.character(caption) || length(caption) != 1 || is.na(caption)) {
        stop("The caption is missing")
    }
    caption <- stringr::str_squish(caption)
    if (nchar(caption) < 200) stop("The caption is too short (", nchar(caption), " characters)")
    if (nchar(caption) > 4000) stop("The caption is too long (", nchar(caption), " characters)")
    if (stringr::str_detect(caption, "\\*\\*|__|(^|\\s)#{1,6}\\s")) stop("The caption contains markdown")
    caption
}

# The year and the event come from the real list, never from the model's memory
check_event <- function(x, events) {
    choice <- suppressWarnings(as.integer(x$choice))
    if (length(choice) != 1 || is.na(choice) || choice < 1 || choice > nrow(events)) {
        stop("The model chose event number ", x$choice, ", which is not in the list of ", nrow(events))
    }
    list(
        year    = events$year[choice],
        event   = events$text[choice],
        caption = clean_caption(x$caption)
    )
}

# A positive historical event for `date`: list(year, event, caption). `events` is
# the real list for the date (fetched from Wikipedia unless given).
generate_event <- function(date, events = fetch_onthisday(date)) {
    openai_text_json(
        event_system_message,
        event_user_prompt(date, events),
        "historical_event",
        event_schema
    ) |>
        check_event(events)
}

# A different event, when the first one could not be illustrated
generate_alternative_event <- function(date, rejected_caption, events = fetch_onthisday(date)) {
    openai_text_json(
        alternative_system_message,
        alternative_user_prompt(date, events, rejected_caption),
        "historical_event",
        event_schema
    ) |>
        check_event(events)
}

# The same event described so that the safety system accepts it: a caption
sanitize_caption <- function(caption) {
    openai_text_json(
        sanitize_system_message,
        sanitize_user_prompt(caption),
        "sanitized_caption",
        caption_schema
    )$caption |>
        clean_caption()
}

# Images ----

# The image as raw PNG bytes
generate_image <- function(prompt) {
    body <- list(
        model   = openai_image_model,
        prompt  = paste0(prompt, openai_image_prompt_suffix),
        n       = 1,
        size    = openai_image_size,
        quality = openai_image_quality
    )

    b64 <- openai_perform("https://api.openai.com/v1/images/generations", body, max_tries = 3, backoff = 60) |>
        httr2::resp_body_json() |>
        purrr::pluck("data", 1, "b64_json")

    if (is.null(b64)) stop("The image API returned no image")
    jsonlite::base64_dec(b64)
}

# Was the request turned down by the safety system (the only error a rewrite can fix)?
is_moderation_block <- function(e) {
    inherits(e, "httr2_http_400") && identical(openai_error_code(e$resp), "moderation_blocked")
}

# NULL when the safety system blocked the prompt; every other error stops the script
try_generate_image <- function(prompt) {
    tryCatch(
        generate_image(prompt),
        error = function(e) {
            if (!is_moderation_block(e)) stop(e)
            cat("Blocked by the safety system:", conditionMessage(e), "\n")
            NULL
        }
    )
}

# Create the image for `caption`. If the safety system blocks it, try a rewritten
# caption, then a different event. Returns list(image, caption, changed).
generate_image_with_fallbacks <- function(caption, date) {
    image <- try_generate_image(caption)
    if (!is.null(image)) return(list(image = image, caption = caption, changed = FALSE))

    cat("Retrying with a rewritten caption...\n")
    rewritten <- sanitize_caption(caption)
    image <- try_generate_image(rewritten)
    if (!is.null(image)) return(list(image = image, caption = rewritten, changed = TRUE))

    cat("Retrying with a different event...\n")
    alternative <- generate_alternative_event(date, caption)
    cat("Alternative event:", alternative$year, "-", alternative$event, "\n")
    image <- try_generate_image(alternative$caption)
    if (!is.null(image)) return(list(image = image, caption = alternative$caption, changed = TRUE))

    stop("The safety system blocked the original, the rewritten and the alternative description")
}
