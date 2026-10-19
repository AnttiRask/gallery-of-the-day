# Real events for a date, from Wikipedia's "On this day" feed. Needs httr2, dplyr, purrr.
#
# The feed is the source of truth for what happened on a date and in which year,
# so the text model only chooses and describes; it does not recall.
# Wikipedia's text is available under CC BY-SA 4.0 (credited in the app footer).

onthisday_url <- function(date) {
    sprintf(
        "https://api.wikimedia.org/feed/v1/wikipedia/en/onthisday/events/%s/%s",
        format(date, "%m"),
        format(date, "%d")
    )
}

# One row per event: year (negative for BCE), text, page (title of the main article)
empty_onthisday <- function() {
    dplyr::tibble(year = integer(), text = character(), page = character())
}

parse_onthisday <- function(body) {
    if (length(body$events) == 0) return(empty_onthisday())

    events <- purrr::map(body$events, \(e) {
        list(
            year = suppressWarnings(as.integer(e$year)),
            text = e$text %||% NA_character_,
            page = purrr::pluck(e, "pages", 1, "normalizedtitle", .default = NA_character_)
        )
    })

    dplyr::bind_rows(events) |>
        dplyr::filter(!is.na(year), !is.na(text), nzchar(text)) |>
        dplyr::arrange(year)
}

fetch_onthisday <- function(date) {
    body <- httr2::request(onthisday_url(date)) |>
        # Wikimedia asks API clients to identify themselves
        httr2::req_user_agent("GalleryOfTheDay/1.0 (https://galleryoftheday.youcanbeapirate.com; https://github.com/AnttiRask/gallery-of-the-day)") |>
        httr2::req_timeout(60) |>
        httr2::req_retry(max_tries = 4, retry_on_failure = TRUE, backoff = \(i) 10 * i) |>
        httr2::req_perform() |>
        httr2::resp_body_json()

    events <- parse_onthisday(body)
    if (nrow(events) == 0) stop("Wikipedia returned no events for ", format(date, "%m/%d"))
    events
}
