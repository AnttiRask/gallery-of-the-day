library(testthat)

source("../../R/wikipedia.R")

# A trimmed copy of the feed's shape: BCE year, a string year, a missing text, a missing page
feed_body <- list(events = list(
    list(year = 1969, text = "Apollo 11 lands on the Moon.", pages = list(list(normalizedtitle = "Apollo 11"))),
    list(year = -331, text = "Alexander the Great defeats Darius III.", pages = list(list(normalizedtitle = "Battle of Gaugamela"))),
    list(year = "1900", text = "Max Planck discovers Planck's law.", pages = list()),
    list(year = 1850, text = "", pages = list()),
    list(year = "unknown", text = "No usable year.", pages = list())
))

feed_response <- function(body = feed_body, status = 200) {
    httr2::response(
        status_code = status,
        headers     = list(`Content-Type` = "application/json"),
        body        = charToRaw(jsonlite::toJSON(body, auto_unbox = TRUE))
    )
}

test_that("the feed URL has a two-digit month and day", {
    expect_equal(
        onthisday_url(as.Date("2026-07-05")),
        "https://api.wikimedia.org/feed/v1/wikipedia/en/onthisday/events/07/05"
    )
})

test_that("events are parsed, cleaned and sorted by year", {
    events <- parse_onthisday(feed_body)

    expect_named(events, c("year", "text", "page"))
    expect_equal(events$year, c(-331L, 1900L, 1969L))
    expect_equal(events$text[3], "Apollo 11 lands on the Moon.")
    expect_equal(events$page, c("Battle of Gaugamela", NA, "Apollo 11"))
})

test_that("fetch_onthisday identifies the app and returns the events", {
    seen <- NULL
    httr2::local_mocked_responses(function(req) {
        seen <<- req
        feed_response()
    })

    events <- fetch_onthisday(as.Date("2026-07-20"))

    expect_equal(nrow(events), 3)
    expect_match(seen$url, "events/07/20", fixed = TRUE)
    expect_match(seen$options$useragent, "GalleryOfTheDay", fixed = TRUE)
    # contact is by URL; no personal address in the code
    expect_false(grepl("@", seen$options$useragent, fixed = TRUE))
})

test_that("an empty feed is an error, not an empty list", {
    httr2::local_mocked_responses(function(req) feed_response(list(events = list())))

    expect_error(fetch_onthisday(as.Date("2026-07-20")), "no events")
})

test_that("a failing feed is an error", {
    httr2::local_mocked_responses(function(req) feed_response(list(), status = 500))

    expect_error(fetch_onthisday(as.Date("2026-07-20")))
})
