# Turso Database Helper Functions
# Uses the Turso HTTP API via httr2. Shared by the daily scripts (R/) and the Shiny
# app (app/global.R sources this file; the Dockerfile copies it into the image).
# Credentials come from the TURSO_DATABASE_URL and TURSO_AUTH_TOKEN environment
# variables, or from variables of the same name (the app's config.R sets them).

library(httr2)
library(jsonlite)

# Convert libsql:// URL to https:// for HTTP API
convert_to_https <- function(url) {
    gsub("^libsql://", "https://", url)
}

# A setting from the environment, or from a variable of the same name if the
# environment doesn't have it
turso_setting <- function(name) {
    value <- Sys.getenv(name)
    if (value == "" && exists(name)) {
        value <- get(name)
    }
    value
}

# The HTTP request for a SQL statement. `retry` is only for statements that are safe
# to send twice (reads): a write whose answer was lost may already have happened, and
# running it again could duplicate a row (prompts_archive has no unique key) or fail
# with a confusing UNIQUE error (prompts). Reads give up after 8 s and try once more
# after a network error or a 429/5xx (not after other 4xx, such as a bad token);
# writes get 30 s and a single try.
turso_request <- function(sql, params = list(), retry = TRUE) {
    database_url <- convert_to_https(turso_setting("TURSO_DATABASE_URL"))
    auth_token <- turso_setting("TURSO_AUTH_TOKEN")

    # Convert params to Turso's expected format
    args <- lapply(params, function(p) {
        if (is.character(p)) {
            list(type = "text", value = p)
        } else if (is.numeric(p)) {
            list(type = "integer", value = as.character(as.integer(p)))
        } else {
            list(type = "text", value = as.character(p))
        }
    })

    body <- list(
        requests = list(
            list(
                type = "execute",
                stmt = list(
                    sql = sql,
                    args = args
                )
            ),
            list(type = "close")
        )
    )

    req <- request(paste0(database_url, "/v2/pipeline")) %>%
        req_headers(
            Authorization = paste("Bearer", auth_token),
            `Content-Type` = "application/json"
        ) %>%
        req_body_json(body)

    if (retry) {
        req %>%
            req_timeout(8) %>%
            req_retry(
                max_tries        = 2,
                retry_on_failure = TRUE,
                is_transient     = \(resp) resp_status(resp) %in% c(429, 500, 502, 503, 504),
                backoff          = \(i) getOption("turso.retry_pause", 1)
            )
    } else {
        req %>% req_timeout(30)
    }
}

# The first result of a Turso reply, stopping with Turso's own message on an error
turso_first_result <- function(response) {
    result <- resp_body_json(response)

    if (!is.null(result$results[[1]]$error)) {
        stop("Turso error: ", result$results[[1]]$error$message)
    }

    result$results[[1]]$response$result
}

# Execute a SQL query and return results as a data frame
turso_query <- function(sql, params = list()) {
    res <- turso_request(sql, params) %>%
        req_perform() %>%
        turso_first_result()

    if (!is.null(res)) {
        cols <- sapply(res$cols, function(x) x$name)
        rows <- res$rows

        if (length(rows) == 0) {
            # Return empty data frame with correct columns
            df <- as.data.frame(matrix(ncol = length(cols), nrow = 0))
            names(df) <- cols
            return(df)
        }

        # Convert rows to data frame
        df <- do.call(rbind, lapply(rows, function(row) {
            sapply(row, function(cell) {
                if (is.null(cell$value)) NA else cell$value
            })
        }))
        df <- as.data.frame(df, stringsAsFactors = FALSE)
        names(df) <- cols
        return(df)
    }

    return(NULL)
}

# Execute a SQL statement (INSERT, UPDATE, DELETE) - returns affected rows.
# Never retried (see turso_request()).
turso_execute <- function(sql, params = list()) {
    res <- turso_request(sql, params, retry = FALSE) %>%
        req_perform() %>%
        turso_first_result()

    if (!is.null(res)) {
        return(res$affected_row_count)
    }

    return(0)
}
