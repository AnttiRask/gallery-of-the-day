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

# The object name of a day's image
r2_object_key <- function(date) {
    paste0("gallery-of-the-day-", date, ".png")
}

# The bucket as two functions, so the daily flows can be tested with a fake one.
# exists(key) is TRUE only when the object is there (any error counts as "no");
# upload(image, key) puts raw PNG bytes, replacing an object with the same key.
r2_client <- function(account_id, access_key_id, secret_access_key, bucket) {
    endpoint <- paste0(account_id, ".r2.cloudflarestorage.com")

    list(
        exists = function(key) {
            found <- tryCatch(
                aws.s3::head_object(
                    object   = key,
                    bucket   = bucket,
                    key      = access_key_id,
                    secret   = secret_access_key,
                    base_url = endpoint,
                    region   = ""
                ),
                error = function(e) FALSE
            )
            isTRUE(found)
        },
        upload = function(image, key) {
            temp_file <- tempfile(fileext = ".png")
            on.exit(unlink(temp_file))
            writeBin(image, temp_file)
            cat("Uploading to R2:", key, "(bucket", bucket, ", endpoint", endpoint, ")\n")

            r2_put_with_retry(function() {
                aws.s3::put_object(
                    file     = temp_file,
                    object   = key,
                    bucket   = bucket,
                    key      = access_key_id,
                    secret   = secret_access_key,
                    base_url = endpoint,
                    region   = ""
                )
            })
            cat("Image uploaded to R2:", key, "\n")
        }
    )
}
