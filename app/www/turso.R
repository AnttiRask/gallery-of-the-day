# Turso Database Helper Functions for Shiny App
# Uses the Turso HTTP API via httr2

library(httr2)
library(jsonlite)

# Convert libsql:// URL to https:// for HTTP API
convert_to_https <- function(url) {
    gsub("^libsql://", "https://", url)
}

# Execute a SQL query and return results as a data frame
turso_query <- function(sql, params = list()) {
    # Get credentials from config (sourced in server.R)
    database_url <- convert_to_https(TURSO_DATABASE_URL)
    auth_token <- TURSO_AUTH_TOKEN

    # Build the request body
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

    # Make the request
    response <- request(paste0(database_url, "/v2/pipeline")) %>%
        req_headers(
            Authorization = paste("Bearer", auth_token),
            `Content-Type` = "application/json"
        ) %>%
        req_body_json(body) %>%
        req_perform()

    # Parse response
    result <- resp_body_json(response)

    # Check for errors
    if (!is.null(result$results[[1]]$error)) {
        stop("Turso error: ", result$results[[1]]$error$message)
    }

    # Extract data and convert to data frame
    if (!is.null(result$results[[1]]$response$result)) {
        res <- result$results[[1]]$response$result
        cols <- sapply(res$cols, function(x) x$name)
        rows <- res$rows

        if (length(rows) == 0) {
            df <- as.data.frame(matrix(ncol = length(cols), nrow = 0))
            names(df) <- cols
            return(df)
        }

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
