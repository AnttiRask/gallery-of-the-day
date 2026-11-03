# The flows of the daily scripts, as functions. create_prompt.R, fetch_image.R and
# backfill_date.R only read the environment, load packages and call these; the
# Turso, R2 and OpenAI calls are arguments (the real ones by default), so the
# tests run every path with fakes and nothing touches a service.
#
# Needs R/config.R, R/openai.R and R/turso.R sourced first.

# Today's (or `date`'s) caption into Turso, unless it is already there.
# Returns "skipped" or "created".
create_daily_prompt <- function(date,
                                query    = turso_query,
                                execute  = turso_execute,
                                generate = generate_event) {
    date_str <- as.character(date)
    existing <- query("SELECT COUNT(*) as count FROM prompts WHERE date = ?", list(date_str))

    if (as.integer(existing$count[1]) > 0) {
        cat("Prompt for", date_str, "already exists. Skipping.\n")
        return(invisible("skipped"))
    }

    cat("Asking", openai_text_model, "for an event on", date_label(date), "...\n")
    event <- generate(date)

    cat("Event:", year_label(event$year), "-", event$event, "\n")
    cat("Generated prompt length:", nchar(event$caption), "characters\n")

    cat("Saving to Turso database...\n")
    execute("INSERT INTO prompts (text, date) VALUES (?, ?)", list(event$caption, date_str))
    cat("Prompt saved for", date_str, "\n")

    invisible("created")
}

# The image for `date` into R2, unless it is already there. The caption must
# already be in Turso; if a safety block made the model change it, Turso gets the
# version that worked (before the upload, as always). Returns "skipped" or "uploaded".
fetch_daily_image <- function(date, r2,
                              query          = turso_query,
                              execute        = turso_execute,
                              generate_image = generate_image_with_fallbacks) {
    date_str   <- as.character(date)
    object_key <- r2_object_key(date_str)

    if (r2$exists(object_key)) {
        cat("Image for", date_str, "already exists in R2. Skipping.\n")
        return(invisible("skipped"))
    }

    prompt_result <- query("SELECT text FROM prompts WHERE date = ?", list(date_str))
    if (nrow(prompt_result) == 0 || is.na(prompt_result$text[1]) || prompt_result$text[1] == "") {
        stop("There is no prompt for ", date_str, " in Turso. Run R/create_prompt.R first.")
    }
    prompt <- prompt_result$text[1]
    cat("Prompt length:", nchar(prompt), "characters\n")

    cat("Making", openai_image_model, "request...\n")
    result <- generate_image(prompt, date)

    if (result$changed) {
        cat("Updating prompt in Turso with the successful version...\n")
        execute("UPDATE prompts SET text = ? WHERE date = ?", list(result$caption, date_str))
    }

    r2$upload(result$image, object_key)
    cat("Done!\n")

    invisible("uploaded")
}

# Fills one past day (backfill_date.R). Skips what exists, so it is safe to re-run.
# With regenerate = TRUE a new event and image are made first and Turso is
# updated only after the upload, so a failure leaves the old day as it was.
# Returns "regenerated", "complete" (nothing left to do) or "backfilled".
backfill_day <- function(date, r2, regenerate = FALSE,
                         query          = turso_query,
                         execute        = turso_execute,
                         generate       = generate_event,
                         generate_image = generate_image_with_fallbacks) {
    date_str   <- as.character(date)
    object_key <- r2_object_key(date_str)

    save_caption <- function(caption) {
        existing <- query("SELECT COUNT(*) as count FROM prompts WHERE date = ?", list(date_str))
        if (as.integer(existing$count[1]) > 0) {
            execute("UPDATE prompts SET text = ? WHERE date = ?", list(caption, date_str))
        } else {
            execute("INSERT INTO prompts (text, date) VALUES (?, ?)", list(caption, date_str))
        }
        cat("Prompt saved for", date_str, "\n")
    }

    if (regenerate) {
        cat("Regenerating", date_str, "with", openai_text_model, "and", openai_image_model, "...\n")

        event <- generate(date)
        cat("Event:", year_label(event$year), "-", event$event, "\n")

        result <- generate_image(event$caption, date)

        r2$upload(result$image, object_key)
        save_caption(result$caption)

        cat("Done regenerating", date_str, "\n")
        return(invisible("regenerated"))
    }

    # Step 1: a prompt in Turso
    existing <- query("SELECT text FROM prompts WHERE date = ?", list(date_str))

    if (nrow(existing) > 0 && !is.na(existing$text[1]) && nchar(existing$text[1]) > 0) {
        cat("Prompt for", date_str, "already exists in Turso. Reusing it.\n")
        prompt_text <- existing$text[1]
    } else {
        cat("Asking", openai_text_model, "for an event on", date_label(date), "...\n")

        event <- generate(date)
        prompt_text <- event$caption

        cat("Event:", year_label(event$year), "-", event$event, "\n")
        cat("Generated prompt length:", nchar(prompt_text), "characters\n")

        save_caption(prompt_text)
    }

    # Step 2: an image in R2
    if (r2$exists(object_key)) {
        cat("Image for", date_str, "already in R2. Done.\n")
        return(invisible("complete"))
    }

    cat("Making", openai_image_model, "request for", date_str, "...\n")
    result <- generate_image(prompt_text, date)

    if (result$changed) {
        cat("Updating Turso prompt to the version that succeeded.\n")
        save_caption(result$caption)
    }

    r2$upload(result$image, object_key)
    cat("Done backfilling", date_str, "\n")

    invisible("backfilled")
}
