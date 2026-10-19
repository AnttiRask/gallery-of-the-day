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
                div(
                    class = "d-flex justify-content-center gap-3 flex-wrap",
                    if(current_app != "bibliostatus")
                        a(href = "https://bibliostatus.youcanbeapirate.com", "BiblioStatus"),
                    if(current_app != "fillaristatus")
                        a(href = "https://fillaristatus.youcanbeapirate.com", "FillariStatus"),
                    if(current_app != "gallery")
                        a(href = "https://galleryoftheday.youcanbeapirate.com", "Gallery of the Day"),
                    if(current_app != "trackteller")
                        a(href = "https://trackteller.youcanbeapirate.com", "TrackTeller"),
                    if(current_app != "tuneteller")
                        a(href = "https://tuneteller.youcanbeapirate.com", "TuneTeller")
                )
            ),
            div(
                class = "footer-credit",
                p(
                    "Created by ",
                    a(href = "https://www.linkedin.com/in/AnttiRask", "Antti Rask"),
                    " | ",
                    a(href = "https://youcanbeapirate.com", "youcanbeapirate.com")
                )
            )
        )
    )
}

# youcanbeapirate brand, the same as the other apps. Brand red is for chrome only;
# `red_on_dark` is a lighter red for text and links on the dark background (brand
# red is only 3.1:1 there, this is 6.2:1)
brand_colours <- list(
    red         = "#C1272D",
    red_on_dark = "#F26B70",
    dark_bg     = "#191414"
)

gotham_css_url <- "https://fonts.cdnfonts.com/css/gotham-6"

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
        `data-label-to-light` = "Switch to light mode",
        `data-label-to-dark` = "Switch to dark mode",
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
    title = "Gallery of the Day",
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
        # Lightbox and keyboard navigation functionality
        tags$script(HTML("
            $(document).ready(function() {
                // Delegate click handler for gallery images (rendered dynamically by renderUI)
                $(document).on('click', '.gallery-image', function(e) {
                    e.preventDefault();
                    var imgSrc = $(this).attr('src');
                    var imgAlt = $(this).attr('alt');

                    // Create lightbox HTML
                    var lightbox = $('<div>', {
                        id: 'image-lightbox',
                        class: 'lightbox-overlay',
                        html: '<div class=\"lightbox-content\">' +
                              '<button class=\"lightbox-close\" aria-label=\"Close lightbox\">&times;</button>' +
                              '<img src=\"' + imgSrc + '\" alt=\"' + imgAlt + '\" class=\"lightbox-image\">' +
                              '</div>'
                    });

                    // Append and fade in
                    $('body').append(lightbox);
                    setTimeout(function() {
                        lightbox.addClass('lightbox-visible');
                    }, 10);

                    // Prevent body scroll
                    $('body').css('overflow', 'hidden');
                });

                // Close on backdrop click
                $(document).on('click', '.lightbox-overlay', function(e) {
                    if (e.target === this) {
                        closeLightbox();
                    }
                });

                // Close on X button
                $(document).on('click', '.lightbox-close', function(e) {
                    e.stopPropagation();
                    closeLightbox();
                });

                // Close on Escape key
                $(document).on('keydown', function(e) {
                    if (e.key === 'Escape' && $('#image-lightbox').length > 0) {
                        closeLightbox();
                    }
                });

                function closeLightbox() {
                    var lightbox = $('#image-lightbox');
                    lightbox.removeClass('lightbox-visible');
                    setTimeout(function() {
                        lightbox.remove();
                        $('body').css('overflow', '');
                    }, 300); // Match CSS transition duration
                }

                // Store available dates and current date for keyboard navigation
                var availableDates = [];
                var currentDateIndex = -1;

                // Receive available dates from server
                Shiny.addCustomMessageHandler('updateAvailableDates', function(message) {
                    availableDates = message.dates;
                    console.log('Received available dates from server:', availableDates.length, 'dates');

                    // Initialize current date index (wrapped in try-catch for timing issues)
                    try {
                        var initialDate = Shiny.inputBindings.getBindings()
                            .find(b => b.binding.name === 'shiny.dateInput')
                            ?.binding.getValue($('#dateInput')[0]);
                        if (initialDate) {
                            currentDateIndex = availableDates.indexOf(initialDate);
                        }
                    } catch (e) {
                        // Datepicker not ready yet - currentDateIndex will be set by shiny:inputchanged event
                        console.log('Initial date not available yet, will be set on first change');
                    }
                });

                // Update current date index when Shiny updates the date
                $(document).on('shiny:inputchanged', function(event) {
                    if (event.name === 'dateInput' && availableDates.length > 0) {
                        currentDateIndex = availableDates.indexOf(event.value);
                    }
                });

                // Keyboard navigation for date selection
                $(document).on('keydown', function(e) {
                    // Don't navigate if lightbox is open or user is typing in an input
                    if ($('#image-lightbox').length > 0 || $(e.target).is('input, textarea, select')) {
                        return;
                    }

                    // Only handle arrow keys
                    if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') {
                        return;
                    }

                    // Check if we have dates and a valid current index
                    if (availableDates.length === 0 || currentDateIndex === -1) {
                        return;
                    }

                    var newIndex = -1;

                    // Left arrow - previous date
                    if (e.key === 'ArrowLeft') {
                        e.preventDefault();
                        newIndex = currentDateIndex - 1;
                        if (newIndex >= 0) {
                            var newDate = availableDates[newIndex];
                            currentDateIndex = newIndex;  // Update immediately

                            // Update datepicker widget using Shiny's binding API
                            var binding = Shiny.inputBindings.getBindings()
                                .find(b => b.binding.name === 'shiny.dateInput')?.binding;
                            if (binding) {
                                binding.setValue($('#dateInput')[0], newDate);
                            }

                            // Update Shiny's reactive value
                            Shiny.setInputValue('dateInput', newDate, {priority: 'event'});
                        }
                    }

                    // Right arrow - next date
                    if (e.key === 'ArrowRight') {
                        e.preventDefault();
                        newIndex = currentDateIndex + 1;
                        if (newIndex < availableDates.length) {
                            var newDate = availableDates[newIndex];
                            currentDateIndex = newIndex;  // Update immediately

                            // Update datepicker widget using Shiny's binding API
                            var binding = Shiny.inputBindings.getBindings()
                                .find(b => b.binding.name === 'shiny.dateInput')?.binding;
                            if (binding) {
                                binding.setValue($('#dateInput')[0], newDate);
                            }

                            // Update Shiny's reactive value
                            Shiny.setInputValue('dateInput', newDate, {priority: 'event'});
                        }
                    }
                });
            });
        "))
    ),

    div(
        class = "gallery-container",

        # Title and the light/dark switch
        div(
            class = "gallery-header",
            # First word in the brand colour, like the other apps' titles
            h1(
                class = "display-3 gallery-title",
                HTML('<span class="gallery-title-accent">Gallery</span> of the Day')
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
                tags$em(
                    "Historical events and images are generated with AI. ",
                    "The events are chosen from Wikipedia's \"On this day\" lists (CC BY-SA 4.0). ",
                    "While based on real events, details should be verified with authoritative sources. ",
                    "Images are artistic interpretations, not historical photographs."
                )
            )
        )
    ),

    # Add footer with cross-linking
    create_app_footer("gallery")
)
