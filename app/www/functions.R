add_spaces_after_periods <- function(text) {
    str_replace_all(text, "\\.(?! )", ". ")
}

insert_row_breaks <- function(text, max_length = 400) {
    
    # Split the text into sentences
    sentences <- unlist(str_split(text, "(?<=[.!?])\\s+"))
    new_text <- ""
    current_length <- 0
    
    # Concatenate sentences with double breaks if the sentence length exceeds max_length
    for (sentence in sentences) {
        # Trim sentence to remove leading and trailing whitespaces
        sentence <- str_trim(sentence)
        if (nchar(sentence) + current_length > max_length) {
            new_text <- str_c(new_text, "\n\n", sentence)
            current_length <- nchar(sentence)
        } else {
            # If this is not the first sentence, add it with a space
            if (nchar(new_text) > 0) {
                new_text <- str_c(new_text, " ", sentence)
            } else {
                new_text <- sentence
            }
            current_length <- current_length + nchar(sentence) + 1
        }
    }
    
    return(new_text)
}

clean_and_break_text <- function(text) {
    text %>%
        add_spaces_after_periods() %>%
        insert_row_breaks()
}

# A quiet message in place of the image (and the date picker and caption) when
# something is missing. `retry` adds a button that reloads the page (see
# lightbox.js).
state_message <- function(text, retry = FALSE) {
    div(
        class = "state-message text-center",
        role  = "status",
        p(text),
        if (retry) {
            tags$button(
                type  = "button",
                class = "btn btn-outline-secondary btn-sm state-retry",
                strings$try_again
            )
        }
    )
}


# A quiet note above the image when the newest image is more than `limit` days
# old (for example after failed daily runs); NULL when the data is fresh.
# `newest` is a date or a "YYYY-MM-DD" string; `today` is in UTC like the daily run.
stale_note <- function(newest, today = as.Date(Sys.time(), tz = "UTC"), limit = stale_after_days) {
    newest <- as.Date(newest)
    if (is.na(newest) || as.numeric(today - newest) <= limit) {
        return(NULL)
    }
    p(
        class = "stale-note small text-muted text-center",
        role  = "status",
        sprintf(strings$stale, format(newest, "%Y-%m-%d"))
    )
}
