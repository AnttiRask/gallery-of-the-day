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

# Prompts ----

# "October 1" (no leading zero)
date_label <- function(date) {
    paste(format(date, "%B"), as.integer(format(date, "%d")))
}

event_system_message <- "You are a cultural historian specializing in positive human achievements, scientific discoveries, and artistic milestones. You NEVER describe violence, conflict, or tragedy. Your role is to find the most visually compelling, uplifting historical moments suitable for beautiful AI-generated artwork."

event_output_format <- "OUTPUT FORMAT:
Return JSON with three fields: year (the year of the event, as a number), event (a short plain-text name of the event, at most 12 words), and caption (the visual description).
The caption must be plain prose in one or two paragraphs of about 150 to 250 words. Do not use markdown, headings, bullet points or bold text. Begin the caption with the date, the year and the name of the event (for example: \"On July 20, 1969, ...\").
Do not mention brand names, trademarked or copyrighted characters, or logos."

event_user_prompt <- function(date) {
    label <- date_label(date)
    paste0(
        "You must provide a vivid visual description of a historical event from ", label, " that is suitable for AI image generation.

REQUIREMENTS - You MUST choose from these categories ONLY:
1. Scientific discoveries or technological breakthroughs
2. Cultural celebrations, festivals, or traditions
3. Artistic achievements (music premiers, art unveilings, literary milestones)
4. Sports achievements or inaugural events
5. Space exploration milestones
6. Peaceful diplomatic achievements or treaty signings
7. Architectural completions or inaugurations
8. Conservation or humanitarian milestones

STRICT PROHIBITIONS - NEVER describe:
- Wars, battles, military conflicts, or violence of any kind
- Weapons, armor, or military equipment
- Tragedies, disasters, assassinations, or deaths
- Political controversies or protests

VISUAL DESCRIPTION FORMAT:
Describe the scene with vivid details: the setting, the people involved (their clothing, expressions, poses), the atmosphere (lighting, weather, mood), and significant objects or symbols. Focus on creating a visually compelling, uplifting image that celebrates human achievement or cultural heritage.

You MUST select an event from exactly ", label, ". If no event perfectly matches all categories above, choose the most positive and visually compelling event that occurred on this exact date in any year throughout history. Be certain that the event really happened on this date.

",
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

alternative_user_prompt <- function(date, rejected_caption) {
    paste0(
        "I need a DIFFERENT historical event for ", date_label(date), " than this one, which could not be illustrated:\n\n",
        substr(rejected_caption, 1, 200), "...\n\n",
        "Choose an event that is:
- Peaceful, celebratory, or scientifically/culturally significant
- NOT related to wars, conflicts, tragedies, or controversial topics
- Visually interesting (art, science discoveries, cultural celebrations, sports achievements, space exploration, etc.)
- Real and on exactly this date

Focus on elements that would make a beautiful, uplifting image: the setting, the people involved, their clothing, and the atmosphere.

",
        event_output_format
    )
}
