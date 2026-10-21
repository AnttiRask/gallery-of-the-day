library(testthat)

source(test_path("../../app/www/variables.R"), local = TRUE)
source(test_path("../../app/www/security.R"), local = TRUE)
source(test_path("../../app/www/health.R"), local = TRUE)

TODAY <- as.Date("2026-10-21")

# Helpers ----

data_from <- function(newest) {
    list(status = "ok", data = data.frame(date = as.character(newest), text = "A fine day.", stringsAsFactors = FALSE))
}

empty_cache <- function() {
    cache <- new.env(parent = emptyenv())
    cache$failure <- NULL
    cache
}

failing_cache <- function() {
    cache <- empty_cache()
    cache$failure <- list(status = "unavailable", data = NULL)
    cache
}

health <- function(loaded, cache = empty_cache()) {
    health_status(loaded = loaded, cache = cache, today = TODAY, max_age_days = 1)
}

# health_status ----

test_that("fresh data and a working Turso is ok", {
    res <- health(data_from(TODAY))
    expect_true(res$ok)
    expect_equal(res$body, "ok")
})

test_that("yesterday's image is still ok (the daily run is at 04:00 UTC and can be late)", {
    expect_true(health(data_from(TODAY - 1))$ok)
})

test_that("two days without a new image is stale, and the reason names the date", {
    res <- health(data_from(TODAY - 2))
    expect_false(res$ok)
    expect_equal(res$body, "stale: the newest image is from 2026-10-19")
})

test_that("the newest of several dates counts", {
    loaded <- list(status = "ok", data = data.frame(date = c("2026-01-01", "2026-10-21", "2026-05-05"), text = "x"))
    expect_true(health(loaded)$ok)
})

test_that("an unreadable date is reported, not crashed on", {
    res <- health(data_from("not a date"))
    expect_false(res$ok)
    expect_match(res$body, "^stale: the newest date can't be read")
})

test_that("no prompts available is unavailable; an empty table is empty", {
    expect_equal(health(list(status = "unavailable", data = NULL))$body, "unavailable: the prompts can't be loaded")
    expect_equal(health(list(status = "empty", data = NULL))$body, "empty: there are no prompts")
    expect_false(health(list(status = "unavailable", data = NULL))$ok)
})

test_that("serving the cached copy because refreshing fails is degraded, even though the page looks fine", {
    res <- health(data_from(TODAY), cache = failing_cache())
    expect_false(res$ok)
    expect_equal(res$body, "degraded: serving the cached prompts because refreshing them fails")
})

test_that("stale and degraded are both reported", {
    res <- health(data_from(TODAY - 5), cache = failing_cache())
    expect_match(res$body, "^stale: .*; degraded: ")
})

test_that("the answer carries no error details", {
    for (res in list(health(list(status = "unavailable", data = NULL)), health(data_from(TODAY - 3), failing_cache()))) {
        expect_false(grepl("HTTP|401|500|token|secret|libsql|turso\\.io", res$body, ignore.case = TRUE))
    }
})

test_that("the limit is one day", {
    expect_equal(health_max_age_days, 1)
})

# with_health_check ----

fake_app <- function(handler) structure(list(httpHandler = handler), class = "shiny.appobj")
pass_through <- function(req) shiny::httpResponse(200, "text/html", "<p>the app</p>")

test_that("GET /health answers 200 ok, as plain text that is never cached", {
    app <- with_health_check(fake_app(pass_through), check = function() list(ok = TRUE, body = "ok"))
    res <- app$httpHandler(list(PATH_INFO = "/health", REQUEST_METHOD = "GET"))
    expect_equal(res$status, 200L)
    expect_equal(res$content, "ok")
    expect_match(res$content_type, "^text/plain")
    expect_equal(res$headers[["Cache-Control"]], "no-store")
})

test_that("a problem is a 503 with the reason", {
    app <- with_health_check(fake_app(pass_through), check = function() list(ok = FALSE, body = "stale: the newest image is from 2026-10-01"))
    res <- app$httpHandler(list(PATH_INFO = "/health", REQUEST_METHOD = "GET"))
    expect_equal(res$status, 503L)
    expect_equal(res$content, "stale: the newest image is from 2026-10-01")
})

test_that("HEAD works too, other methods and other paths go to the app", {
    app <- with_health_check(fake_app(pass_through), check = function() list(ok = TRUE, body = "ok"))
    expect_equal(app$httpHandler(list(PATH_INFO = "/health", REQUEST_METHOD = "HEAD"))$status, 200L)
    expect_equal(app$httpHandler(list(PATH_INFO = "/health", REQUEST_METHOD = "POST"))$content, "<p>the app</p>")
    expect_equal(app$httpHandler(list(PATH_INFO = "/", REQUEST_METHOD = "GET"))$content, "<p>the app</p>")
    expect_equal(app$httpHandler(list(PATH_INFO = "/health/more", REQUEST_METHOD = "GET"))$content, "<p>the app</p>")
})

test_that("NULL answers and promises from the app still pass through", {
    app <- with_health_check(fake_app(function(req) NULL))
    expect_null(app$httpHandler(list(PATH_INFO = "/other", REQUEST_METHOD = "GET")))

    app <- with_health_check(fake_app(function(req) promises::promise_resolve(shiny::httpResponse(200, "text/html", "later"))))
    res <- NULL
    promises::then(app$httpHandler(list(PATH_INFO = "/x", REQUEST_METHOD = "GET")), function(value) res <<- value)
    while (is.null(res)) later::run_now(0.1)
    expect_equal(res$content, "later")
})

test_that("if the check itself breaks, the answer is a 503, not an R error page", {
    app <- with_health_check(fake_app(pass_through), check = function() stop("boom with a secret path /etc/x"))
    res <- suppressMessages(app$httpHandler(list(PATH_INFO = "/health", REQUEST_METHOD = "GET")))
    expect_equal(res$status, 503L)
    expect_equal(res$content, "unavailable: the health check itself failed")
    expect_false(grepl("boom|secret", res$content))
})

test_that("inside the security wrapper the health answer gets the security headers", {
    app <- with_security_headers(with_health_check(fake_app(pass_through), check = function() list(ok = TRUE, body = "ok")))
    res <- app$httpHandler(list(PATH_INFO = "/health", REQUEST_METHOD = "GET"))
    expect_equal(res$status, 200L)
    expect_equal(res$headers[["X-Frame-Options"]], "DENY")
    expect_equal(res$headers[["X-Content-Type-Options"]], "nosniff")
    expect_equal(res$headers[["Cache-Control"]], "no-store")
})

test_that("with the default check, it asks load_prompts() and the prompts cache", {
    # health_status() finds both by name, as run.R's global environment does
    where <- environment(health_status)
    assign("load_prompts", function() data_from(as.Date(Sys.time(), tz = "UTC")), envir = where)
    assign("prompts_cache", empty_cache(), envir = where)
    withr::defer(rm(list = c("load_prompts", "prompts_cache"), envir = where))
    expect_true(health_status()$ok)
})
