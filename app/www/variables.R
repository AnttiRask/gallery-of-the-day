## Settings shared by run.R (security headers), config.R and ui.R. Everything in www/ is
## served publicly: never put a secret in this file.

# Public URL of the Cloudflare R2 bucket the images come from. The R2_PUBLIC_URL
# environment variable overrides it; local development uses this default.
r2_public_url_default <- "https://pub-fa8ba5f601374e88994818db80a1c9d2.r2.dev"

# How old the newest image may get before the page says so. The daily run is at
# 04:00 UTC and GitHub sometimes starts it hours late (08:59 once), so one missed
# day must not trigger the note.
stale_after_days <- 2

# youcanbeapirate brand, the same as the other apps. Brand red is for chrome only;
# `red_on_dark` is a lighter red for text and links on the dark background (brand
# red is only 3.1:1 there, this is 6.2:1)
brand_colours <- list(
    red         = "#C1272D",
    red_on_dark = "#F26B70",
    dark_bg     = "#191414"
)

gotham_css_url <- "https://fonts.cdnfonts.com/css/gotham-6"

# The apps linked in every footer (the current app is left out of its own footer;
# `id` is what create_app_footer() is called with)
footer_apps <- list(
    list(id = "bibliostatus",  name = "BiblioStatus",       url = "https://bibliostatus.youcanbeapirate.com"),
    list(id = "fillaristatus", name = "FillariStatus",      url = "https://fillaristatus.youcanbeapirate.com"),
    list(id = "gallery",       name = "Gallery of the Day", url = "https://galleryoftheday.youcanbeapirate.com"),
    list(id = "trackteller",   name = "TrackTeller",        url = "https://trackteller.youcanbeapirate.com"),
    list(id = "tuneteller",    name = "TuneTeller",         url = "https://tuneteller.youcanbeapirate.com")
)

footer_credit <- list(
    author_name = "Antti Rask",
    author_url  = "https://www.linkedin.com/in/AnttiRask",
    site_name   = "youcanbeapirate.com",
    site_url    = "https://youcanbeapirate.com"
)
