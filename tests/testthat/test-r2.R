library(testthat)

source("../../R/r2.R")

test_that("a put that works is called once", {
    calls <- 0
    expect_true(r2_put_with_retry(function() calls <<- calls + 1, pause = 0))
    expect_equal(calls, 1)
})

test_that("a 502 is retried and the upload then succeeds", {
    calls <- 0
    put <- function() {
        calls <<- calls + 1
        if (calls < 3) stop("Bad Gateway (HTTP 502).", call. = FALSE)
    }
    capture.output(result <- r2_put_with_retry(put, pause = 0))
    expect_true(result)
    expect_equal(calls, 3)
})

test_that("it gives up after max_tries with a clear error", {
    calls <- 0
    put <- function() { calls <<- calls + 1; stop("Service Unavailable (HTTP 503).", call. = FALSE) }
    capture.output(expect_error(r2_put_with_retry(put, max_tries = 3, pause = 0), "Failed to upload image to R2"))
    expect_equal(calls, 3)
})

test_that("a rejected request (4xx) is not retried", {
    calls <- 0
    put <- function() { calls <<- calls + 1; stop("Forbidden (HTTP 403).", call. = FALSE) }
    capture.output(expect_error(r2_put_with_retry(put, pause = 0), "Failed to upload image to R2"))
    expect_equal(calls, 1)
})

test_that("a connection error without a status is treated as transient", {
    expect_true(is_transient_r2("Could not resolve host"))
    expect_false(is_transient_r2("Forbidden (HTTP 403)."))
})
