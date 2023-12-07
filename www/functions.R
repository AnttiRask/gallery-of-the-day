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