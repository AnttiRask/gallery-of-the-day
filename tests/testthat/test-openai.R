library(testthat)

source("../../R/config.R")
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

event_content <- function(year = 1969, event = "Apollo 11 Moon Landing", caption = long_text()) {
    jsonlite::toJSON(list(year = year, event = event, caption = caption), auto_unbox = TRUE)
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

# Mock the API: a queue of responses per endpoint; calls are counted and bodies kept
mock_openai <- function(chat = list(), images = list(), env = parent.frame()) {
    state <- new.env()
    state$chat <- chat
    state$images <- images
    state$calls <- list(chat = 0, images = 0)
    state$bodies <- list()

    httr2::local_mocked_responses(function(req) {
        endpoint <- if (grepl("chat/completions", req$url)) "chat" else "images"
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

# Text ----

test_that("generate_event returns the parsed event", {
    setup_env()
    mock_openai(chat = list(chat_response(event_content())))

    event <- generate_event(as.Date("2026-07-20"))

    expect_equal(event$year, 1969L)
    expect_equal(event$event, "Apollo 11 Moon Landing")
    expect_gte(nchar(event$caption), 200)
})

test_that("the text request names the model, switches reasoning off and asks for a strict JSON schema", {
    setup_env()
    state <- mock_openai(chat = list(chat_response(event_content())))

    generate_event(as.Date("2026-07-20"))
    body <- state$bodies[[1]]

    expect_equal(body$model, openai_text_model)
    expect_equal(body$reasoning_effort, "none")
    expect_equal(body$response_format$type, "json_schema")
    expect_true(body$response_format$json_schema$strict)
    expect_equal(unlist(body$response_format$json_schema$schema$required), c("year", "event", "caption"))
    expect_match(body$messages[[2]]$content, "July 20", fixed = TRUE)
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
    expect_error(generate_event(date), "valid JSON")

    mock_openai(chat = list(chat_response(event_content(), finish_reason = "length")))
    expect_error(generate_event(date), "did not finish")

    mock_openai(chat = list(chat_response("", refusal = "I can't help with that")))
    expect_error(generate_event(date), "refused")

    mock_openai(chat = list(chat_response(event_content(caption = paste("**Apollo 11**", long_text())))))
    expect_error(generate_event(date), "markdown")

    mock_openai(chat = list(chat_response(event_content(caption = "Too short"))))
    expect_error(generate_event(date), "too short")

    mock_openai(chat = list(chat_response(event_content(year = 3000))))
    expect_error(generate_event(date), "sensible year")
})

test_that("an empty balance fails with OpenAI's own message", {
    setup_env()
    mock_openai(chat = list(api_error(429, "insufficient_quota", "You have no credits remaining.")))

    expect_error(generate_event(as.Date("2026-07-20")), "no credits remaining")
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
})

test_that("when the rewrite is blocked too, a different event is used", {
    setup_env()
    state <- mock_openai(
        images = list(api_error(400, "moderation_blocked"), api_error(400, "moderation_blocked"), image_response()),
        chat   = list(
            chat_response(jsonlite::toJSON(list(caption = long_text(400)), auto_unbox = TRUE)),
            chat_response(event_content(year = 1908, event = "Model T introduced", caption = long_text(500)))
        )
    )

    result <- generate_image_with_fallbacks(long_text(), as.Date("2026-10-01"))

    expect_true(result$changed)
    expect_equal(result$caption, clean_caption(long_text(500)))
    expect_equal(state$calls$images, 3)
    # the rejected event is passed on so the model picks another one
    expect_match(state$bodies[[4]]$messages[[2]]$content, "DIFFERENT", fixed = TRUE)
})

test_that("three blocks in a row end in an error", {
    setup_env()
    mock_openai(
        images = rep(list(api_error(400, "moderation_blocked")), 3),
        chat   = list(
            chat_response(jsonlite::toJSON(list(caption = long_text(400)), auto_unbox = TRUE)),
            chat_response(event_content())
        )
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
