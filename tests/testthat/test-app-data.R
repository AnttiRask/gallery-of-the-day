library(testthat)

# turso_query() reads these like the app does (config.R sets them from the environment)
TURSO_DATABASE_URL <- "libsql://test-db.turso.io"
TURSO_AUTH_TOKEN   <- "not-a-real-token"

source(test_path("../../app/www/variables.R"), local = TRUE)
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
    httr2::with_mocked_responses(m$mock, suppressMessages(fetch_prompts()))
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
        httr2::with_mocked_responses(m$mock, fetch_prompts()),
        "Loading the prompts failed"
    )
})

# The cache ----
# A fake fetcher and a fake clock, so no network and no waiting. `T0` is any start time.

T0 <- as.POSIXct("2026-10-20 12:00:00", tz = "UTC")
minutes <- function(n) n * 60

good_result <- function(label = "v1") {
    list(status = "ok", data = data.frame(date = "2026-10-20", text = label, stringsAsFactors = FALSE))
}
down <- list(status = "unavailable", data = NULL)

# A fetcher that returns the given results in order (the last one repeats) and counts calls
fake_fetch <- function(...) {
    results <- list(...)
    calls <- 0
    list(
        fetch = function() {
            calls <<- calls + 1
            results[[min(calls, length(results))]]
        },
        calls = function() calls
    )
}

cached <- function(f, at, cache, ...) {
    suppressMessages(load_prompts(now = T0 + at, fetch = f$fetch, cache = cache, ...))
}

test_that("a fresh copy is used without asking Turso again", {
    cache <- new_prompts_cache(); f <- fake_fetch(good_result())
    expect_equal(cached(f, 0, cache)$status, "ok")
    cached(f, minutes(1), cache); cached(f, minutes(4.9), cache)
    expect_equal(f$calls(), 1)
})

test_that("after 5 minutes Turso is asked again and a new copy replaces the old one", {
    cache <- new_prompts_cache(); f <- fake_fetch(good_result("v1"), good_result("v2"))
    cached(f, 0, cache)
    res <- cached(f, minutes(5), cache)
    expect_equal(f$calls(), 2)
    expect_equal(res$data$text, "v2")
    # and the new copy is fresh for another 5 minutes
    cached(f, minutes(9), cache)
    expect_equal(f$calls(), 2)
})

test_that("when Turso fails the old copy is served, with no error", {
    cache <- new_prompts_cache(); f <- fake_fetch(good_result("v1"), down)
    cached(f, 0, cache)
    res <- cached(f, minutes(10), cache)
    expect_equal(res$status, "ok")
    expect_equal(res$data$text, "v1")
    expect_equal(f$calls(), 2)
})

test_that("the failure is logged when the old copy is served", {
    cache <- new_prompts_cache(); f <- fake_fetch(good_result("v1"), down)
    cached(f, 0, cache)
    expect_message(load_prompts(now = T0 + minutes(10), fetch = f$fetch, cache = cache),
                   "Serving the cached prompts")
})

test_that("after a failure Turso is left alone for 30 s, then tried again", {
    cache <- new_prompts_cache(); f <- fake_fetch(good_result("v1"), down, good_result("v2"))
    cached(f, 0, cache)
    cached(f, minutes(10), cache)                       # fails (call 2)
    res <- cached(f, minutes(10) + 29, cache)            # within 30 s: no new call
    expect_equal(f$calls(), 2)
    expect_equal(res$data$text, "v1")
    res <- cached(f, minutes(10) + 31, cache)            # after 30 s: tries again (call 3)
    expect_equal(f$calls(), 3)
    expect_equal(res$data$text, "v2")
})

test_that("with no copy, a failure shows unavailable, and the next visitor within 30 s doesn't wait", {
    cache <- new_prompts_cache(); f <- fake_fetch(down, good_result())
    expect_equal(cached(f, 0, cache)$status, "unavailable")
    expect_equal(cached(f, 10, cache)$status, "unavailable")
    expect_equal(f$calls(), 1)
    expect_equal(cached(f, 31, cache)$status, "ok")      # recovers
    expect_equal(f$calls(), 2)
})

test_that("an empty table never replaces good data", {
    cache <- new_prompts_cache(); f <- fake_fetch(good_result("v1"), list(status = "empty", data = NULL))
    cached(f, 0, cache)
    res <- cached(f, minutes(10), cache)
    expect_equal(res$status, "ok")
    expect_equal(res$data$text, "v1")
})

test_that("with no copy an empty table is reported as empty", {
    cache <- new_prompts_cache(); f <- fake_fetch(list(status = "empty", data = NULL))
    expect_equal(cached(f, 0, cache)$status, "empty")
})

test_that("the old copy is served for 7 days, then the failure shows", {
    cache <- new_prompts_cache(); f <- fake_fetch(good_result("v1"), down)
    cached(f, 0, cache)
    day <- 24 * 60 * 60
    expect_equal(cached(f, 6.9 * day, cache)$status, "ok")
    expect_equal(cached(f, 7.1 * day, cache)$status, "unavailable")
})

test_that("it recovers by itself after the cap when Turso comes back", {
    cache <- new_prompts_cache(); f <- fake_fetch(good_result("v1"), down, good_result("v3"))
    cached(f, 0, cache)
    day <- 24 * 60 * 60
    expect_equal(cached(f, 8 * day, cache)$status, "unavailable")
    res <- cached(f, 8 * day + 60, cache)
    expect_equal(res$data$text, "v3")
})

test_that("the settings are 5 minutes, 30 seconds and 7 days", {
    expect_equal(prompts_cache_seconds, 300)
    expect_equal(prompts_retry_seconds, 30)
    expect_equal(prompts_max_age_seconds, 7 * 24 * 60 * 60)
})
