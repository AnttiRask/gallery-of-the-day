library(testthat)

source("../../R/config.R")
source("../../R/wikipedia.R")
source("../../R/openai.R")

# Helpers ----

json_response <- function(body, status = 200) {
    httr2::response(
        status_code = status,
        headers     = list(`Content-Type` = "application/json"),
        body        = charToRaw(jsonlite::toJSON(body, auto_unbox = TRUE, null = "null"))
    )
}

api_error <- function(status, code, message = "An error") {
    json_response(list(error = list(message = message, type = "invalid_request_error", code = code)), status)
}

long_text <- function(n = 300) paste(rep("word", n / 5), collapse = " ")

# The real events for a date (normally fetched from Wikipedia)
sample_events <- data.frame(
    year = c(1900L, 1969L, 1908L),
    text = c(
        "Max Planck discovers Planck's law of black-body radiation.",
        "Apollo 11 lands on the Moon.",
        "Ford Model T automobiles are offered for sale."
    )
)

event_content <- function(choice = 2, caption = long_text()) {
    jsonlite::toJSON(list(choice = choice, caption = caption), auto_unbox = TRUE)
}

chat_response <- function(content, finish_reason = "stop", refusal = NULL) {
    json_response(list(choices = list(list(
        finish_reason = finish_reason,
        message       = list(content = as.character(content), refusal = refusal)
    ))))
}

image_response <- function() {
    json_response(list(data = list(list(b64_json = jsonlite::base64_enc(charToRaw("PNGDATA"))))))
}

onthisday_response <- function() {
    json_response(list(events = lapply(seq_len(nrow(sample_events)), function(i) {
        list(year = sample_events$year[i], text = sample_events$text[i], pages = list(list(normalizedtitle = paste("Page", i))))
    })))
}

# Mock the APIs: a queue of responses per endpoint; calls are counted and bodies kept
mock_openai <- function(chat = list(), images = list(), wiki = list(), env = parent.frame()) {
    state <- new.env()
    state$chat <- chat
    state$images <- images
    state$wiki <- wiki
    state$calls <- list(chat = 0, images = 0, wiki = 0)
    state$bodies <- list()

    httr2::local_mocked_responses(function(req) {
        endpoint <- if (grepl("chat/completions", req$url)) "chat" else if (grepl("onthisday", req$url)) "wiki" else "images"
        state$calls[[endpoint]] <- state$calls[[endpoint]] + 1
        state$bodies[[length(state$bodies) + 1]] <- req$body$data
        queue <- state[[endpoint]]
        stopifnot(length(queue) > 0)
        state[[endpoint]] <- queue[-1]
        queue[[1]]
    }, env = env)

    state
}

setup_env <- function(env = parent.frame()) {
    withr::local_envvar(OPENAI_API_KEY = "test-key", .local_envir = env)
    withr::local_options(openai.retry_backoff = 0, .local_envir = env)
}

# The text of every chat request that was sent
chat_prompts <- function(state) {
    unlist(lapply(state$bodies, function(b) if (!is.null(b$messages)) b$messages[[2]]$content))
}

# Text ----

test_that("generate_event takes the year and the event from the real list, not from the model", {
    setup_env()
    mock_openai(chat = list(chat_response(event_content(choice = 2))))

    event <- generate_event(as.Date("2026-07-20"), sample_events)

    expect_equal(event$year, 1969L)
    expect_equal(event$event, "Apollo 11 lands on the Moon.")
    expect_gte(nchar(event$caption), 200)
})

test_that("the text request lists the events and asks for a strict JSON schema with reasoning off", {
    setup_env()
    state <- mock_openai(chat = list(chat_response(event_content())))

    generate_event(as.Date("2026-07-20"), sample_events)
    body <- state$bodies[[1]]

    expect_equal(body$model, openai_text_model)
    expect_equal(body$reasoning_effort, "none")
    expect_equal(body$response_format$type, "json_schema")
    expect_true(body$response_format$json_schema$strict)
    expect_equal(unlist(body$response_format$json_schema$schema$required), c("choice", "caption"))
    prompt <- body$messages[[2]]$content
    expect_match(prompt, "July 20", fixed = TRUE)
    expect_match(prompt, "1. [1900] Max Planck discovers", fixed = TRUE)
    expect_match(prompt, "2. [1969] Apollo 11 lands on the Moon.", fixed = TRUE)
})

test_that("years before the common era are labelled BCE in the list", {
    expect_equal(year_label(c(-331, 1900)), c("331 BCE", "1900"))
    expect_match(format_event_list(data.frame(year = -331L, text = "A battle.")), "1. [331 BCE] A battle.", fixed = TRUE)
})

test_that("the preferred category rotates with the day of the year and appears in the prompt", {
    expect_equal(preferred_category(as.Date("2026-01-01")), event_category_names[1])
    expect_equal(preferred_category(as.Date("2026-01-02")), event_category_names[2])
    expect_equal(preferred_category(as.Date("2026-01-09")), event_category_names[1])  # 8 categories
    expect_setequal(preferred_category(as.Date("2026-01-01") + 0:7), event_category_names)

    prompt <- event_user_prompt(as.Date("2026-01-03"), sample_events)
    expect_match(prompt, paste0("prefer an event in this category if one fits well: ", event_category_names[3]), fixed = TRUE)
    # a nudge, not a rule: the other categories stay allowed
    expect_match(prompt, "from any category", fixed = TRUE)
})

test_that("the one-field schema keeps `required` an array", {
    json <- jsonlite::toJSON(caption_schema, auto_unbox = TRUE)
    expect_match(as.character(json), "\"required\":[\"caption\"]", fixed = TRUE)
})

test_that("the date label has no leading zero", {
    expect_equal(date_label(as.Date("2026-10-01")), "October 1")
    expect_equal(date_label(as.Date("2026-12-25")), "December 25")
})

test_that("bad text-model output is an error, never a caption", {
    setup_env()
    date <- as.Date("2026-07-20")

    mock_openai(chat = list(chat_response("not json")))
    expect_error(generate_event(date, sample_events), "valid JSON")

    mock_openai(chat = list(chat_response(event_content(), finish_reason = "length")))
    expect_error(generate_event(date, sample_events), "did not finish")

    mock_openai(chat = list(chat_response("", refusal = "I can't help with that")))
    expect_error(generate_event(date, sample_events), "refused")

    mock_openai(chat = list(chat_response(event_content(caption = paste("**Apollo 11**", long_text())))))
    expect_error(generate_event(date, sample_events), "markdown")

    mock_openai(chat = list(chat_response(event_content(caption = "Too short"))))
    expect_error(generate_event(date, sample_events), "too short")
})

test_that("a choice that is not in the list is an error", {
    setup_env()
    date <- as.Date("2026-07-20")

    mock_openai(chat = list(chat_response(event_content(choice = 0))))
    expect_error(generate_event(date, sample_events), "not in the list")

    mock_openai(chat = list(chat_response(event_content(choice = 99))))
    expect_error(generate_event(date, sample_events), "not in the list")
})

test_that("an empty balance fails with OpenAI's own message", {
    setup_env()
    mock_openai(chat = list(api_error(429, "insufficient_quota", "You have no credits remaining.")))

    expect_error(generate_event(as.Date("2026-07-20"), sample_events), "no credits remaining")
})

# httr2 does not retry mocked responses, so the retry decision is tested on its own
test_that("only rate limits and server errors are worth retrying, an empty balance is not", {
    expect_true(is_transient_openai(api_error(429, "rate_limit_exceeded")))
    expect_true(is_transient_openai(api_error(500, NULL)))
    expect_true(is_transient_openai(api_error(503, NULL)))
    expect_false(is_transient_openai(api_error(429, "insufficient_quota")))
    expect_false(is_transient_openai(api_error(400, "moderation_blocked")))
    expect_false(is_transient_openai(api_error(401, "invalid_api_key")))
    expect_false(is_transient_openai(json_response(list(ok = TRUE))))
})

test_that("a missing key is a clear error", {
    withr::local_envvar(OPENAI_API_KEY = "")
    expect_error(openai_key(), "OPENAI_API_KEY is not set")
})

# Images ----

test_that("generate_image returns the decoded bytes and sends the configured model", {
    setup_env()
    state <- mock_openai(images = list(image_response()))

    image <- generate_image("A prompt")

    expect_equal(rawToChar(image), "PNGDATA")
    # the no-text instruction goes to the image API only
    expect_equal(state$bodies[[1]]$prompt, paste0("A prompt", openai_image_prompt_suffix))
    expect_match(state$bodies[[1]]$prompt, "must not contain any text", fixed = TRUE)
    expect_equal(state$bodies[[1]]$model, openai_image_model)
    expect_equal(state$bodies[[1]]$quality, openai_image_quality)
    expect_equal(state$bodies[[1]]$size, openai_image_size)
})

test_that("only a moderation block counts as a safety rejection", {
    setup_env()

    mock_openai(images = list(api_error(400, "moderation_blocked", "Rejected by the safety system.")))
    err <- tryCatch(generate_image("x"), error = identity)
    expect_true(is_moderation_block(err))
    expect_match(conditionMessage(err), "safety system")

    mock_openai(images = list(api_error(400, "invalid_value", "Unknown parameter")))
    err <- tryCatch(generate_image("x"), error = identity)
    expect_false(is_moderation_block(err))
    expect_match(conditionMessage(err), "Unknown parameter")
})

test_that("a blocked caption is retried once with a rewritten caption", {
    setup_env()
    rewritten <- long_text(400)
    state <- mock_openai(
        images = list(api_error(400, "moderation_blocked"), image_response()),
        chat   = list(chat_response(jsonlite::toJSON(list(caption = rewritten), auto_unbox = TRUE)))
    )

    result <- generate_image_with_fallbacks(long_text(), as.Date("2026-10-01"))

    expect_true(result$changed)
    expect_equal(result$caption, rewritten)
    expect_equal(state$calls$images, 2)
    expect_equal(state$calls$chat, 1)
    expect_equal(state$calls$wiki, 0)
})

test_that("when the rewrite is blocked too, a different real event is used", {
    setup_env()
    state <- mock_openai(
        images = list(api_error(400, "moderation_blocked"), api_error(400, "moderation_blocked"), image_response()),
        chat   = list(
            chat_response(jsonlite::toJSON(list(caption = long_text(400)), auto_unbox = TRUE)),
            chat_response(event_content(choice = 3, caption = long_text(500)))
        ),
        wiki   = list(onthisday_response())
    )

    result <- generate_image_with_fallbacks(long_text(), as.Date("2026-10-01"))

    expect_true(result$changed)
    expect_equal(result$caption, clean_caption(long_text(500)))
    expect_equal(state$calls$images, 3)
    expect_equal(state$calls$wiki, 1)
    # the rejected event is passed on, together with the real list, so the model picks another one
    alternative_prompt <- chat_prompts(state)[2]
    expect_match(alternative_prompt, "DIFFERENT", fixed = TRUE)
    expect_match(alternative_prompt, "2. [1908] Ford Model T", fixed = TRUE)  # the list is sorted by year
})

test_that("three blocks in a row end in an error", {
    setup_env()
    mock_openai(
        images = rep(list(api_error(400, "moderation_blocked")), 3),
        chat   = list(
            chat_response(jsonlite::toJSON(list(caption = long_text(400)), auto_unbox = TRUE)),
            chat_response(event_content())
        ),
        wiki   = list(onthisday_response())
    )

    expect_error(generate_image_with_fallbacks(long_text(), as.Date("2026-10-01")), "blocked the original")
})

test_that("no fallback runs for errors a rewrite cannot fix", {
    setup_env()
    state <- mock_openai(images = list(api_error(401, "invalid_api_key", "Incorrect API key")))

    expect_error(generate_image_with_fallbacks(long_text(), as.Date("2026-10-01")), "Incorrect API key")
    expect_equal(state$calls$images, 1)
    expect_equal(state$calls$chat, 0)
})

test_that("an unchanged caption is reported as unchanged", {
    setup_env()
    mock_openai(images = list(image_response()))

    result <- generate_image_with_fallbacks(long_text(), as.Date("2026-10-01"))

    expect_false(result$changed)
    expect_equal(result$caption, long_text())
})
