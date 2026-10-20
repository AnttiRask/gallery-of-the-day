# Shared footer component for cross-linking between apps (the list is in variables.R)
create_app_footer <- function(current_app = "") {
    # Base R only: the Docker image doesn't include purrr
    other_apps <- Filter(\(app) app$id != current_app, footer_apps)
    app_links  <- lapply(other_apps, \(app) a(href = app$url, app$name))

    tags$footer(
        class = "app-footer mt-5 py-4 border-top",
        div(
            class = "container text-center",
            div(
                class = "footer-apps mb-3",
                div(
                    class = "d-flex justify-content-center gap-3 flex-wrap",
                    app_links
                )
            ),
            div(
                class = "footer-credit",
                p(
                    "Created by ",
                    a(href = footer_credit$author_url, footer_credit$author_name),
                    " | ",
                    a(href = footer_credit$site_url, footer_credit$site_name)
                )
            )
        )
    )
}

# Versioned asset URLs, so browsers don't keep serving a stale stylesheet or
# script after a change or a deploy
asset <- function(file) {
    paste0(file, "?v=", as.integer(file.mtime(file.path("www", file))))
}

# The light/dark switch. Its icon shows the mode a click switches to: a sun while
# dark, a moon while light (CSS). mode-toggle.js flips Bootstrap's data-bs-theme.
mode_toggle_button <- function() {
    # Feather icons (MIT)
    icon <- function(class, ...) {
        tags$svg(
            class = paste("gallery-mode-icon", class),
            viewBox = "0 0 24 24",
            width = "22",
            height = "22",
            fill = "none",
            stroke = "currentColor",
            `stroke-width` = "2",
            `stroke-linecap` = "round",
            `stroke-linejoin` = "round",
            `aria-hidden` = "true",
            ...
        )
    }

    tags$button(
        id = "mode-toggle",
        type = "button",
        class = "gallery-mode-button",
        `data-label-to-light` = strings$mode_to_light,
        `data-label-to-dark` = strings$mode_to_dark,
        icon(
            "gallery-icon-sun",
            tags$circle(cx = "12", cy = "12", r = "5"),
            tags$path(d = "M12 1v2M12 21v2M4.22 4.22l1.42 1.42M18.36 18.36l1.42 1.42M1 12h2M21 12h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42")
        ),
        icon(
            "gallery-icon-moon",
            tags$path(d = "M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z")
        )
    )
}

ui <- page_fluid(
    title = strings$app_title,
    theme = bs_theme(
        version = 5,
        primary = brand_colours$red,
        base_font = font_collection(
            font_link("Gotham", href = gotham_css_url),
            "system-ui", "-apple-system", "Segoe UI", "Roboto",
            "Helvetica Neue", "Arial", "sans-serif"
        )
    ) |>
        # Bootstrap's dark-mode palette, in the brand dark background and with a
        # lighter brand red for links
        bs_add_variables(
            "body-bg-dark"          = brand_colours$dark_bg,
            "link-color-dark"       = brand_colours$red_on_dark,
            "link-hover-color-dark" = brand_colours$red_on_dark
        ),

    tags$head(
        # Colours that differ between the modes, from one place
        tags$style(HTML(paste0(
            ":root{--gallery-accent:", brand_colours$red, ";--gallery-frame:#B2B2B2;--gallery-shadow:rgba(0,0,0,0.25);}",
            "[data-bs-theme=dark]{--gallery-accent:", brand_colours$red_on_dark, ";--gallery-frame:#C0C0C0;--gallery-shadow:rgba(0,0,0,0.5);}"
        ))),
        tags$link(rel = "shortcut icon", type = "image/png", href = "favicon.png"),
        tags$link(
            rel  = "stylesheet",
            type = "text/css",
            href = asset("styles.css")
        ),
        # Sets the page to dark straight away, so it must load in the head
        tags$script(src = asset("mode-toggle.js")),
        # Lightbox and keyboard navigation
        tags$script(src = asset("lightbox.js"))
    ),

    div(
        class = "gallery-container",

        # Title and the light/dark switch
        div(
            class = "gallery-header",
            # First word in the brand colour, like the other apps' titles
            h1(
                class = "display-3 gallery-title",
                span(class = "gallery-title-accent", strings$title_accent),
                paste("", strings$title_rest)
            ),
            mode_toggle_button()
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
        ),

        # AI disclaimer
        div(
            class = "ai-disclaimer text-center mt-4",
            p(
                class = "small text-muted",
                tags$em(paste(strings$disclaimer, collapse = ""))
            )
        )
    ),

    # Add footer with cross-linking
    create_app_footer("gallery")
)
