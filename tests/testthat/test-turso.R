library(testthat)

source(test_path("../../R/turso.R"), local = TRUE)

# Helpers ----

cell <- function(x) list(type = "text", value = x)

query_reply <- function(cols, rows) {
    httr2::response_json(body = list(results = list(
        list(type = "ok", response = list(type = "execute", result = list(
            cols = lapply(cols, \(name) list(name = name)),
            rows = lapply(rows, \(row) lapply(row, cell))
        ))),
        list(type = "ok", response = list(type = "close"))
    )))
}

execute_reply <- function(affected) {
    httr2::response_json(body = list(results = list(
        list(type = "ok", response = list(type = "execute", result = list(affected_row_count = affected))),
        list(type = "ok", response = list(type = "close"))
    )))
}

error_reply <- function(message) {
    httr2::response_json(body = list(results = list(
        list(type = "error", error = list(message = message))
    )))
}

# Runs `code` with every request answered by `response`, and returns the request
sent_request <- function(response, code) {
    seen <- NULL
    httr2::with_mocked_responses(function(req) { seen <<- req; response }, code)
    seen
}

headers <- function(req) httr2::req_get_headers(req, redacted = "reveal")

# Credentials ----

test_that("a libsql:// URL becomes https://", {
    expect_equal(convert_to_https("libsql://db-name.turso.io"), "https://db-name.turso.io")
    expect_equal(convert_to_https("https://db-name.turso.io"), "https://db-name.turso.io")
})

test_that("settings come from the environment, or from a variable of the same name", {
    withr::local_envvar(TURSO_DATABASE_URL = "libsql://from-env.turso.io", TURSO_AUTH_TOKEN = "env-token")
    # a variable where the functions look for it (the app's config.R sets globals)
    where <- environment(turso_setting)
    assign("TURSO_DATABASE_URL", "libsql://from-variable.turso.io", envir = where)
    withr::defer(rm("TURSO_DATABASE_URL", envir = where))
    expect_equal(turso_setting("TURSO_DATABASE_URL"), "libsql://from-env.turso.io")

    withr::local_envvar(TURSO_DATABASE_URL = "", TURSO_AUTH_TOKEN = "")
    expect_equal(turso_setting("TURSO_DATABASE_URL"), "libsql://from-variable.turso.io")
    expect_equal(turso_setting("TURSO_AUTH_TOKEN"), "")        # nowhere: empty, not an error
})

test_that("nobody passes credentials as arguments any more", {
    expect_false("database_url" %in% names(formals(turso_query)))
    expect_false("auth_token" %in% names(formals(turso_execute)))
})

# The request ----

test_that("the request goes to the pipeline URL with the token and a JSON body", {
    withr::local_envvar(TURSO_DATABASE_URL = "libsql://test-db.turso.io", TURSO_AUTH_TOKEN = "secret-token")
    req <- turso_request("SELECT 1")
    expect_equal(req$url, "https://test-db.turso.io/v2/pipeline")
    expect_equal(headers(req)[["Authorization"]], "Bearer secret-token")
    expect_equal(headers(req)[["Content-Type"]], "application/json")
    expect_equal(req$body$data$requests[[1]]$stmt$sql, "SELECT 1")
    expect_equal(req$body$data$requests[[2]]$type, "close")
})

test_that("parameters are sent as text or integer values", {
    withr::local_envvar(TURSO_DATABASE_URL = "libsql://test-db.turso.io", TURSO_AUTH_TOKEN = "t")
    args <- turso_request("SELECT ?, ?, ?", list("a \"quoted\" ü", 7.9, TRUE))$body$data$requests[[1]]$stmt$args
    expect_equal(args[[1]], list(type = "text", value = "a \"quoted\" ü"))
    expect_equal(args[[2]], list(type = "integer", value = "7"))
    expect_equal(args[[3]], list(type = "text", value = "TRUE"))
})

# Reads and writes get different safety ----

test_that("reads time out after 8 s and try at most twice, on transient errors only", {
    withr::local_envvar(TURSO_DATABASE_URL = "libsql://t.turso.io", TURSO_AUTH_TOKEN = "t")
    req <- turso_request("SELECT 1")
    expect_equal(req$options$timeout_ms, 8000)
    expect_equal(req$policies$retry_max_tries, 2)
    expect_true(req$policies$retry_on_failure)
    transient <- req$policies$retry_is_transient
    for (code in c(429, 500, 502, 503, 504)) expect_true(transient(httr2::response(status_code = code)), info = code)
    for (code in c(200, 400, 401, 403, 404)) expect_false(transient(httr2::response(status_code = code)), info = code)
})

test_that("writes are never retried: 30 s and a single try", {
    withr::local_envvar(TURSO_DATABASE_URL = "libsql://t.turso.io", TURSO_AUTH_TOKEN = "t")
    req <- turso_request("INSERT INTO prompts (text, date) VALUES (?, ?)", list("x", "2026-01-01"), retry = FALSE)
    expect_equal(req$options$timeout_ms, 30000)
    expect_null(req$policies$retry_max_tries)
    expect_null(req$policies$retry_on_failure)
})

test_that("turso_execute builds a request without retry, turso_query one with retry", {
    withr::local_envvar(TURSO_DATABASE_URL = "libsql://t.turso.io", TURSO_AUTH_TOKEN = "t")
    written <- sent_request(execute_reply(1), turso_execute("UPDATE prompts SET text = ? WHERE date = ?", list("a", "b")))
    read <- sent_request(query_reply("date", list()), turso_query("SELECT date FROM prompts"))
    expect_null(written$policies$retry_max_tries)
    expect_equal(read$policies$retry_max_tries, 2)
})

# Results ----

test_that("turso_query returns a data frame", {
    withr::local_envvar(TURSO_DATABASE_URL = "libsql://t.turso.io", TURSO_AUTH_TOKEN = "t")
    df <- httr2::with_mocked_responses(
        function(req) query_reply(c("date", "text"), list(c("2026-01-01", "a"), c("2026-01-02", "b"))),
        turso_query("SELECT date, text FROM prompts")
    )
    expect_equal(names(df), c("date", "text"))
    expect_equal(df$text, c("a", "b"))
})

test_that("turso_query with no rows returns an empty data frame that keeps its columns", {
    withr::local_envvar(TURSO_DATABASE_URL = "libsql://t.turso.io", TURSO_AUTH_TOKEN = "t")
    df <- httr2::with_mocked_responses(function(req) query_reply(c("date", "text"), list()), turso_query("SELECT * FROM prompts"))
    expect_equal(nrow(df), 0)
    expect_equal(names(df), c("date", "text"))
})

test_that("turso_execute returns the number of affected rows", {
    withr::local_envvar(TURSO_DATABASE_URL = "libsql://t.turso.io", TURSO_AUTH_TOKEN = "t")
    n <- httr2::with_mocked_responses(function(req) execute_reply(3), turso_execute("DELETE FROM prompts WHERE date < ?", list("2026-01-01")))
    expect_equal(n, 3)
})

test_that("an error from Turso stops with Turso's own message, for reads and writes", {
    withr::local_envvar(TURSO_DATABASE_URL = "libsql://t.turso.io", TURSO_AUTH_TOKEN = "t")
    httr2::with_mocked_responses(function(req) error_reply("no such table: nope"), {
        expect_error(turso_query("SELECT * FROM nope"), "Turso error: no such table: nope")
        expect_error(turso_execute("DELETE FROM nope"), "Turso error: no such table: nope")
    })
})

test_that("an HTTP error stops the call (a bad token is not swallowed)", {
    withr::local_envvar(TURSO_DATABASE_URL = "libsql://t.turso.io", TURSO_AUTH_TOKEN = "wrong")
    httr2::with_mocked_responses(function(req) httr2::response(status_code = 401), {
        expect_error(turso_query("SELECT 1"), "401")
        expect_error(turso_execute("DELETE FROM prompts"), "401")
    })
})
