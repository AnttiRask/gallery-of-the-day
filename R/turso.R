# Turso Database Helper Functions
# Uses the Turso HTTP API via httr2

library(httr2)
library(jsonlite)

# Convert libsql:// URL to https:// for HTTP API
convert_to_https <- function(url) {
    gsub("^libsql://", "https://", url)
}

# Execute a SQL query and return results as a data frame
turso_query <- function(sql, params = list(), database_url = NULL, auth_token = NULL) {
    # Use provided credentials or fall back to environment/global variables
    if (is.null(database_url)) {
        database_url <- Sys.getenv("TURSO_DATABASE_URL")
        if (database_url == "" && exists("TURSO_DATABASE_URL")) {
            database_url <- TURSO_DATABASE_URL
        }
    }
    if (is.null(auth_token)) {
        auth_token <- Sys.getenv("TURSO_AUTH_TOKEN")
        if (auth_token == "" && exists("TURSO_AUTH_TOKEN")) {
            auth_token <- TURSO_AUTH_TOKEN
        }
    }

    # Convert libsql:// to https:// for HTTP API
    database_url <- convert_to_https(database_url)

    # Build the request body
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

# Execute a SQL statement (INSERT, UPDATE, DELETE) - returns affected rows
turso_execute <- function(sql, params = list(), database_url = NULL, auth_token = NULL) {
    # Use provided credentials or fall back to environment/global variables
    if (is.null(database_url)) {
        database_url <- Sys.getenv("TURSO_DATABASE_URL")
        if (database_url == "" && exists("TURSO_DATABASE_URL")) {
            database_url <- TURSO_DATABASE_URL
        }
    }
    if (is.null(auth_token)) {
        auth_token <- Sys.getenv("TURSO_AUTH_TOKEN")
        if (auth_token == "" && exists("TURSO_AUTH_TOKEN")) {
            auth_token <- TURSO_AUTH_TOKEN
        }
    }

    # Convert libsql:// to https:// for HTTP API
    database_url <- convert_to_https(database_url)

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

    # Return affected rows count
    if (!is.null(result$results[[1]]$response$result)) {
        return(result$results[[1]]$response$result$affected_row_count)
    }

    return(0)
}
