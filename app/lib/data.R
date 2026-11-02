# The app's data layer. load_prompts() never throws: the server shows a message for
# each status instead of an R error page. The real error goes to the log
# (Cloud Run's), never to the visitor.
#
# status: "ok" (data has rows), "empty" (the table has no rows), "unavailable"
# (Turso could not be reached or returned an error)

# Reads the prompts from Turso (no cache)
fetch_prompts <- function() {
    data <- tryCatch(
        turso_query("SELECT date, text FROM prompts ORDER BY date"),
        error = function(e) {
            message("Loading the prompts failed: ", conditionMessage(e))
            NULL
        }
    )

    if (!is.data.frame(data) || !all(c("date", "text") %in% names(data))) {
        return(list(status = "unavailable", data = NULL))
    }
    if (nrow(data) == 0) {
        return(list(status = "empty", data = NULL))
    }
    list(status = "ok", data = data)
}

# One cache per R process (Cloud Run runs up to 3 instances, each with its own):
#   data, fetched_at  the last good copy and when it was fetched
#   failure, failed_at  the last failed result and when it failed
new_prompts_cache <- function() {
    cache <- new.env(parent = emptyenv())
    cache$data <- NULL
    cache$fetched_at <- NULL
    cache$failure <- NULL
    cache$failed_at <- NULL
    cache
}

prompts_cache <- new_prompts_cache()

# The prompts, from the cache when it is fresh. Rules:
# 1. A copy younger than prompts_cache_seconds is used as it is.
# 2. Otherwise Turso is asked again, unless it failed less than prompts_retry_seconds
#    ago (then nobody waits for another timeout; the one process serves all sessions
#    one at a time, so a slow Turso would block every visitor).
# 3. Only a good result replaces the cache. An empty table is more likely a fault than
#    a real state, so it never overwrites good data.
# 4. If Turso fails, the old copy is served for up to prompts_max_age_seconds; after
#    that, or with no copy, the page shows the failure.
# `now`, `fetch` and `cache` are only there so tests can control them.
load_prompts <- function(now = Sys.time(), fetch = fetch_prompts, cache = prompts_cache,
                         cache_seconds = prompts_cache_seconds,
                         retry_seconds = prompts_retry_seconds,
                         max_age_seconds = prompts_max_age_seconds) {
    seconds_since <- function(then) as.numeric(now) - as.numeric(then)
    age <- if (is.null(cache$data)) Inf else seconds_since(cache$fetched_at)

    if (age < cache_seconds) {
        return(list(status = "ok", data = cache$data))
    }

    failed_recently <- !is.null(cache$failed_at) && seconds_since(cache$failed_at) < retry_seconds
    if (failed_recently) {
        result <- cache$failure
    } else {
        result <- fetch()
        if (result$status == "ok") {
            cache$data <- result$data
            cache$fetched_at <- now
            cache$failure <- NULL
            cache$failed_at <- NULL
            return(result)
        }
        cache$failure <- result
        cache$failed_at <- now
    }

    if (age < max_age_seconds) {
        if (!failed_recently) {
            message(sprintf("Serving the cached prompts (%.0f min old) because loading them failed",
                            age / 60))
        }
        return(list(status = "ok", data = cache$data))
    }
    result
}
