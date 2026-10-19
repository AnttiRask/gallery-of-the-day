# Settings shared by the daily scripts (create_prompt.R, fetch_image.R, backfill_date.R)

# Month names in the prompts must be English whatever the machine's locale is
invisible(Sys.setlocale("LC_TIME", "C"))

# Models ----

# Writes the event text (chosen after a comparison on 2026-10-19, see
# gallery-of-the-day-refactor-plan.md; gpt-4o-mini is retired on 2027-01-14)
openai_text_model  <- "gpt-5.6-luna"

# Creates the image
openai_image_model <- "gpt-image-2.5-sunburst"
openai_image_size    <- "1024x1024"
openai_image_quality <- "high"

# Added to the image prompt only (not stored with the caption): image models
# invent text, and a wrong date or garbled lettering would spoil the picture
openai_image_prompt_suffix <- "\n\nThe image must not contain any text, letters, numbers, dates, captions, signs or logos."

# Prompts ----

# "October 1" (no leading zero)
date_label <- function(date) {
    paste(format(date, "%B"), as.integer(format(date, "%d")))
}

event_system_message <- "You are a cultural historian specializing in positive human achievements, scientific discoveries, and artistic milestones. You NEVER describe violence, conflict, or tragedy. Your role is to find the most visually compelling, uplifting historical moments suitable for beautiful AI-generated artwork."

# "1969", or "331 BCE" for a negative year
year_label <- function(year) {
    ifelse(year < 0, paste(-year, "BCE"), as.character(year))
}

# The numbered list the model chooses from: "12. [1900] Max Planck discovers ..."
format_event_list <- function(events) {
    paste0(seq_len(nrow(events)), ". [", year_label(events$year), "] ", events$text, collapse = "\n")
}

event_output_format <- "OUTPUT FORMAT:
Return JSON with two fields: choice (the number of the event you chose from the list) and caption (the visual description).
The caption must be plain prose in one or two paragraphs of about 150 to 250 words. Do not use markdown, headings, bullet points or bold text. Begin the caption with the date, the year exactly as shown in the list, and the name of the event (for example: \"On July 20, 1969, ...\").
Describe only what the list entry says happened. Do not add facts you are not sure of, such as names of attendees, quotations or exact numbers.
Do not mention brand names, trademarked or copyrighted characters, or logos."

event_category_names <- c(
    "Scientific discoveries or technological breakthroughs",
    "Cultural celebrations, festivals, or traditions",
    "Artistic achievements (music premiers, art unveilings, literary milestones)",
    "Sports achievements or inaugural events",
    "Space exploration milestones",
    "Peaceful diplomatic achievements or treaty signings",
    "Architectural completions or inaugurations",
    "Conservation or humanitarian milestones"
)

event_categories <- paste0(
    "REQUIREMENTS - the event MUST fit one of these categories ONLY:\n",
    paste0(seq_along(event_category_names), ". ", event_category_names, collapse = "\n"),
    "

STRICT PROHIBITIONS - NEVER choose or describe:
- Wars, battles, military conflicts, or violence of any kind
- Weapons, armor, or military equipment
- Tragedies, disasters, assassinations, or deaths
- Political controversies or protests"
)

# The model drifts towards science and space; rotating the preferred category by
# day of the year keeps the gallery varied without forbidding anything
preferred_category <- function(date) {
    event_category_names[(as.integer(format(date, "%j")) - 1) %% length(event_category_names) + 1]
}

event_visual_format <- "VISUAL DESCRIPTION FORMAT:
Describe the scene with vivid details: the setting, the people involved (their clothing, expressions, poses), the atmosphere (lighting, weather, mood), and significant objects or symbols. Focus on creating a visually compelling, uplifting image that celebrates human achievement or cultural heritage."

# `events` is the real list for the date (see R/wikipedia.R)
event_user_prompt <- function(date, events) {
    paste0(
        "Below is a numbered list of real historical events that happened on ", date_label(date),
        " (the years are correct; the list comes from Wikipedia). Choose exactly ONE of them as the subject of a vivid, image-ready visual description.\n\n",
        event_categories, "\n\n",
        event_visual_format, "\n\n",
        "Today, prefer an event in this category if one fits well: ", preferred_category(date), ". If none does, choose the most positive and visually compelling event from any category that does not break the prohibitions.\n\n",
        "EVENTS:\n", format_event_list(events), "\n\n",
        event_output_format
    )
}

# Used when the image API's safety system rejects a description
sanitize_system_message <- "You are an expert at rewriting historical event descriptions to be suitable for AI image generation. Rewrite the description to focus on peaceful, artistic, and symbolic elements while avoiding any violence, conflict, weapons, or controversial imagery. Remove every brand name, trademarked or copyrighted character, and logo (describe such things generically instead). Keep the historical context."

sanitize_user_prompt <- function(caption) {
    paste0(
        "Rewrite this historical event description so that an image generator's safety system accepts it. Return JSON with one field, caption: the rewritten description as plain prose without markdown, about the same length as the original.\n\n",
        caption
    )
}

# Used when the rewritten description is rejected too
alternative_system_message <- "You are a historian who specializes in finding positive, uplifting historical events suitable for artistic visualization."

alternative_user_prompt <- function(date, events, rejected_caption) {
    paste0(
        "An image could not be made for this event, so I need a DIFFERENT one:\n\n",
        substr(rejected_caption, 1, 200), "...\n\n",
        "Below is a numbered list of real historical events that happened on ", date_label(date),
        " (the years are correct; the list comes from Wikipedia). Choose exactly ONE of them, other than the event above, as the subject of a vivid, image-ready visual description.\n\n",
        event_categories, "\n\n",
        event_visual_format, "\n\n",
        "EVENTS:\n", format_event_list(events), "\n\n",
        event_output_format
    )
}
