library(testthat)

# turso_query() reads these like the app does (config.R sets them from the environment)
TURSO_DATABASE_URL <- "libsql://test-db.turso.io"
TURSO_AUTH_TOKEN   <- "not-a-real-token"

source(test_path("../../app/www/turso.R"), local = TRUE)
source(test_path("../../app/www/data.R"), local = TRUE)

# Helpers ----

turso_ok <- function(rows) {
    cell <- function(x) list(type = "text", value = x)
    httr2::response_json(
        body = list(results = list(
            list(type = "ok", response = list(type = "execute", result = list(
                cols = list(list(name = "date"), list(name = "text")),
                rows = lapply(rows, \(r) list(cell(r[[1]]), cell(r[[2]])))
            ))),
            list(type = "ok", response = list(type = "close"))
        ))
    )
}

# Mock that hands out the given responses in order and counts the calls
sequence_mock <- function(...) {
    responses <- list(...)
    calls <- 0
    list(
        mock  = function(req) {
            calls <<- calls + 1
            responses[[min(calls, length(responses))]]
        },
        calls = function() calls
    )
}

load_quietly <- function(m) {
    withr::local_options(turso.retry_pause = 0)
    httr2::with_mocked_responses(m$mock, suppressMessages(load_prompts()))
}

# Tests ----

test_that("rows from Turso come back as status ok", {
    m <- sequence_mock(turso_ok(list(c("2026-01-01", "First"), c("2026-01-02", "Second"))))
    res <- load_quietly(m)
    expect_equal(res$status, "ok")
    expect_equal(res$data$date, c("2026-01-01", "2026-01-02"))
    expect_equal(m$calls(), 1)
})

test_that("a table without rows is status empty", {
    m <- sequence_mock(turso_ok(list()))
    res <- load_quietly(m)
    expect_equal(res$status, "empty")
    expect_null(res$data)
})

test_that("a bad token (401) is unavailable and is not retried", {
    m <- sequence_mock(httr2::response(status_code = 401))
    res <- load_quietly(m)
    expect_equal(res$status, "unavailable")
    expect_null(res$data)
    expect_equal(m$calls(), 1)
})

test_that("a 500 or a 503 is unavailable", {
    expect_equal(load_quietly(sequence_mock(httr2::response(status_code = 500)))$status, "unavailable")
    expect_equal(load_quietly(sequence_mock(httr2::response(status_code = 503)))$status, "unavailable")
})

# httr2's mocking skips the retry loop, so the policy is checked on the request
# itself; the real behaviour was checked against a local server that answers 500
# first and 200 second (ok after 2 requests), 500 twice (unavailable after exactly 2),
# 401 (unavailable after 1), and a 30 s answer (unavailable after about 17 s).
test_that("the request times out after 8 s and tries at most twice", {
    req <- turso_request("SELECT 1")
    expect_equal(req$options$timeout_ms, 8000)
    expect_equal(req$policies$retry_max_tries, 2)
    expect_true(req$policies$retry_on_failure)
})

test_that("only 429 and 5xx answers are retried, not a bad token or a missing page", {
    transient <- turso_request("SELECT 1")$policies$retry_is_transient
    for (code in c(429, 500, 502, 503, 504)) {
        expect_true(transient(httr2::response(status_code = code)), info = code)
    }
    for (code in c(200, 400, 401, 403, 404)) {
        expect_false(transient(httr2::response(status_code = code)), info = code)
    }
})

test_that("an error reported by Turso itself is unavailable", {
    err <- httr2::response_json(body = list(results = list(
        list(type = "error", error = list(message = "no such table: prompts"))
    )))
    res <- load_quietly(sequence_mock(err))
    expect_equal(res$status, "unavailable")
})

test_that("a reply without the expected columns is unavailable", {
    odd <- httr2::response_json(body = list(results = list(
        list(type = "ok", response = list(type = "execute", result = list(
            cols = list(list(name = "other")),
            rows = list(list(list(type = "text", value = "x")))
        )))
    )))
    res <- load_quietly(sequence_mock(odd))
    expect_equal(res$status, "unavailable")
})

test_that("the real error goes to the log, not to the caller", {
    withr::local_options(turso.retry_pause = 0)
    m <- sequence_mock(httr2::response(status_code = 401))
    expect_message(
        httr2::with_mocked_responses(m$mock, load_prompts()),
        "Loading the prompts failed"
    )
})
