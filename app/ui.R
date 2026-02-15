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

ui <- page_fluid(
    title = "Gallery of the Day",
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
        ),
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
