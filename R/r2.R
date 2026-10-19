# Upload to Cloudflare R2, trying again when R2 has a hiccup.
#
# R2 sometimes answers a PUT with a 502 "internal connectivity issue. Please try
# again." (it stopped one regenerated day on 2026-10-19). A rejected request (a
# 4xx, such as a wrong key) is not retried: waiting won't fix it.

is_transient_r2 <- function(message) {
    !grepl("HTTP 4[0-9]{2}", message)
}

r2_put_with_retry <- function(put, max_tries = 4, pause = getOption("r2.retry_pause", 5)) {
    for (attempt in seq_len(max_tries)) {
        error <- tryCatch({
            put()
            NULL
        }, error = function(e) conditionMessage(e))

        if (is.null(error)) return(invisible(TRUE))

        cat("R2 upload error:", error, "\n")
        if (attempt == max_tries || !is_transient_r2(error)) break

        cat("Trying again in", pause * attempt, "seconds (attempt", attempt + 1, "of", max_tries, ")\n")
        Sys.sleep(pause * attempt)
    }
    stop("Failed to upload image to R2")
}
