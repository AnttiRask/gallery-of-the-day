library(testthat)
library(dplyr)
library(stringr)

# The server function is sourced into its own environment, so each test can swap
# load_prompts() for a fake and check what the page shows in each state.
app_env <- new.env(parent = globalenv())
for (f in c("variables.R", "strings.R", "functions.R")) {
    source(test_path("../../app/www", f), local = app_env)
}
assign("R2_PUBLIC_URL", "https://images.example.com", envir = app_env)
source(test_path("../../app/server.R"), local = app_env)
strings <- app_env$strings

html <- function(x) as.character(x$html)

with_loaded <- function(loaded, code) {
    assign("load_prompts", function() loaded, envir = app_env)
    code
}

two_days <- list(
    status = "ok",
    data = data.frame(
        date = c("2026-01-01", "2026-01-02"),
        text = c("On January 1, something good happened.", "On January 2, something else."),
        stringsAsFactors = FALSE
    )
)

test_that("when the data is available the page shows the image, the caption and the date picker", {
    with_loaded(two_days, shiny::testServer(app_env$server, {
        session$setInputs(dateInput = as.Date("2026-01-02"))
        expect_match(html(output$imageGallery), "gallery-image", fixed = TRUE)
        expect_match(html(output$imageGallery), "gallery-of-the-day-2026-01-02.png", fixed = TRUE)
        expect_match(html(output$imageGallery), htmltools::htmlEscape(strings$image_failed, attribute = TRUE), fixed = TRUE)
        expect_match(html(output$text_with_breaks), "something else", fixed = TRUE)
        expect_match(html(output$dateInput_ui), strings$date_label, fixed = TRUE)
    }))
})

test_that("when Turso is unavailable the page says so and offers a retry", {
    with_loaded(list(status = "unavailable", data = NULL), shiny::testServer(app_env$server, {
        out <- html(output$imageGallery)
        expect_match(out, strings$unavailable, fixed = TRUE)
        expect_match(out, "state-retry", fixed = TRUE)
        expect_match(out, strings$try_again, fixed = TRUE)
        # no raw error text, and no date picker or caption
        expect_false(grepl("Error|HTTP|Turso", out))
        expect_error(output$dateInput_ui)
    }))
})

test_that("an empty table says there are no images yet, without a retry button", {
    with_loaded(list(status = "empty", data = NULL), shiny::testServer(app_env$server, {
        out <- html(output$imageGallery)
        expect_match(out, strings$empty, fixed = TRUE)
        expect_false(grepl("state-retry", out, fixed = TRUE))
    }))
})

test_that("a date without a prompt says there is no image for it", {
    with_loaded(two_days, shiny::testServer(app_env$server, {
        session$setInputs(dateInput = as.Date("2026-01-05"))
        out <- html(output$imageGallery)
        expect_match(out, strings$no_entry, fixed = TRUE)
        expect_false(grepl("<img", out, fixed = TRUE))
    }))
})

# The stale-data note ----

fresh_days <- function(n_old) {
    day <- as.Date(Sys.time(), tz = "UTC") - n_old
    list(status = "ok", data = data.frame(date = as.character(day), text = "A fine day.", stringsAsFactors = FALSE))
}

test_that("stale_note appears only when the newest image is more than the limit old", {
    today <- as.Date("2026-10-20")
    expect_null(app_env$stale_note("2026-10-20", today, limit = 2))
    expect_null(app_env$stale_note("2026-10-19", today, limit = 2))
    expect_null(app_env$stale_note("2026-10-18", today, limit = 2))   # exactly 2 days: still fine
    note <- app_env$stale_note("2026-10-17", today, limit = 2)       # 3 days: say so
    expect_match(as.character(note), "The newest image is from 2026-10-17.", fixed = TRUE)
    expect_match(as.character(note), "stale-note", fixed = TRUE)
    expect_null(app_env$stale_note(NA, today, limit = 2))
})

test_that("the limit comes from variables.R", {
    expect_equal(app_env$stale_after_days, 2)
})

test_that("old data shows the note, in the page", {
    with_loaded(two_days, shiny::testServer(app_env$server, {
        expect_match(html(output$staleNote), "The newest image is from 2026-01-02.", fixed = TRUE)
    }))
})

test_that("fresh data shows no note", {
    with_loaded(fresh_days(0), shiny::testServer(app_env$server, {
        expect_false(any(grepl("stale-note", html(output$staleNote), fixed = TRUE)))
    }))
    with_loaded(fresh_days(2), shiny::testServer(app_env$server, {
        expect_false(any(grepl("stale-note", html(output$staleNote), fixed = TRUE)))
    }))
})

test_that("no data shows no note, only the unavailable message", {
    with_loaded(list(status = "unavailable", data = NULL), shiny::testServer(app_env$server, {
        expect_error(output$staleNote)
    }))
})
