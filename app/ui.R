library(shiny)
library(bslib)

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
    )
)
