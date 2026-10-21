# Health check for the uptime monitor: GET /health (see with_health_check() below,
# wrapped in run.R). 200 and "ok" when the data is healthy, 503 and a short reason
# when it is not. A page that returns 200 on "/" is not enough: the page shell loads
# even when Turso is down or the daily job has failed, and the prompts cache hides
# a Turso outage from visitors. The reasons carry no error details.
#
# Problems reported (joined with "; "):
#   unavailable  the prompts can't be loaded (and there is no cached copy)
#   empty        the table has no rows
#   stale        the newest image is more than health_max_age_days old
#   degraded     the cached copy is being served because refreshing it fails
health_status <- function(loaded = load_prompts(), cache = prompts_cache,
                          today = as.Date(Sys.time(), tz = "UTC"),
                          max_age_days = health_max_age_days) {
    problems <- character()

    if (loaded$status == "unavailable") {
        problems <- c(problems, "unavailable: the prompts can't be loaded")
    } else if (loaded$status == "empty") {
        problems <- c(problems, "empty: there are no prompts")
    } else {
        newest <- as.Date(max(loaded$data$date), optional = TRUE)   # NA, not an error, for a bad date
        if (is.na(newest)) {
            problems <- c(problems, "stale: the newest date can't be read")
        } else if (as.numeric(today - newest) > max_age_days) {
            problems <- c(problems, sprintf("stale: the newest image is from %s", format(newest, "%Y-%m-%d")))
        }
        if (!is.null(cache$failure)) {
            problems <- c(problems, "degraded: serving the cached prompts because refreshing them fails")
        }
    }

    list(ok = length(problems) == 0, body = if (length(problems) == 0) "ok" else paste(problems, collapse = "; "))
}

# Wrap a Shiny app object so GET and HEAD requests for `path` get the health answer
# and everything else goes to the app. Wrap the result with with_security_headers()
# so the answer carries the headers too.
with_health_check <- function(app, path = "/health", check = health_status) {
    original <- app$httpHandler
    app$httpHandler <- function(req) {
        method <- req$REQUEST_METHOD
        if (identical(req$PATH_INFO, path) && (is.null(method) || method %in% c("GET", "HEAD"))) {
            result <- tryCatch(
                check(),
                error = function(e) {
                    message("The health check failed: ", conditionMessage(e))
                    list(ok = FALSE, body = "unavailable: the health check itself failed")
                }
            )
            return(shiny::httpResponse(
                status       = if (result$ok) 200L else 503L,
                content_type = "text/plain; charset=utf-8",
                content      = result$body,
                headers      = list("Cache-Control" = "no-store")
            ))
        }
        original(req)
    }
    app
}
