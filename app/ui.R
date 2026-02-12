library(shiny)
library(bslib)

# Shared footer component for cross-linking between apps
create_app_footer <- function(current_app = "") {
    tags$footer(
        class = "app-footer mt-5 py-4 border-top",
        div(
            class = "container text-center",
            div(
                class = "footer-apps mb-3",
                p(class = "text-muted mb-2", "youcanbeapiRate apps:"),
                div(
                    class = "d-flex justify-content-center gap-3 flex-wrap",
                    if(current_app != "trackteller")
                        a(href = "https://trackteller.youcanbeapirate.com", "TrackTeller"),
                    if(current_app != "tuneteller")
                        a(href = "https://tuneteller.youcanbeapirate.com", "TuneTeller"),
                    if(current_app != "bibliostatus")
                        a(href = "https://bibliostatus.youcanbeapirate.com", "BiblioStatus"),
                    if(current_app != "gallery")
                        a(href = "https://galleryoftheday.youcanbeapirate.com", "Gallery of the Day")
                )
            ),
            div(
                class = "footer-credit",
                p(
                    "Created by ",
                    a(href = "https://anttirask.github.io", "Antti Rask"),
                    " | ",
                    a(href = "https://youcanbeapirate.com", "youcanbeapirate.com")
                )
            )
        )
    )
}

ui <- page_fluid(
    theme = bs_theme(
        version = 5,
        bg = "#000000",
        fg = "#C0C0C0",
        primary = "#C1272D",
        base_font = font_google("EB Garamond"),
        heading_font = font_google("EB Garamond")
    ),

    tags$head(
        tags$link(rel = "shortcut icon", type = "image/png", href = "favicon.png"),
        tags$link(
            rel  = "stylesheet",
            type = "text/css",
            href = "styles.css"
        )
    ),

    div(
        class = "gallery-container",

        # Title
        div(
            class = "text-center my-4",
            h1("Gallery of the Day", class = "display-3")
        ),

        # Image
        uiOutput("imageGallery"),

        # Date picker
        div(
            class = "date-picker-container my-4",
            uiOutput("dateInput_ui")
        ),

        # Caption
        div(
            class = "caption-container",
            htmlOutput("text_with_breaks")
        )
    ),

    # Add footer with cross-linking
    create_app_footer("gallery")
)
