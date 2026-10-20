## All user-facing text of the app, in one place.
## Everything in www/ is served publicly: never put a secret in this file.

strings <- list(
    app_title = "Gallery of the Day",

    # The page heading: the first word is shown in the brand colour
    title_accent = "Gallery",
    title_rest   = "of the Day",

    date_label = "Choose a Date",
    date_aria  = "Date selection for gallery image",

    mode_to_light = "Switch to light mode",
    mode_to_dark  = "Switch to dark mode",

    no_image   = "No image available for this date.",
    no_caption = "No caption available for this date.",

    # Error states (see state_message() in functions.R)
    unavailable  = "The gallery can't load right now. Please try again in a few minutes.",
    empty        = "No images yet.",
    no_entry     = "There is no image for this date.",
    image_failed = "The image for this date couldn't be loaded.",
    try_again    = "Try again",

    # Shown when the newest image is older than stale_after_days; %s is its date
    stale = "The newest image is from %s. New images may be delayed.",

    # Shown under every caption; the sentences are joined with a space
    disclaimer = c(
        "Historical events and images are generated with AI. ",
        "The events are chosen from Wikipedia's \"On this day\" lists (CC BY-SA 4.0). ",
        "While based on real events, details should be verified with authoritative sources. ",
        "Images are artistic interpretations, not historical photographs."
    )
)
