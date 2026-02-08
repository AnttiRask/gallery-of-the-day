# Source functions and config
source("www/functions.R")
source("www/turso.R")
source("config.R")

# Load packages
library(dplyr)
library(shiny)
library(stringr)

server <- function(input, output, session) {

    # Read the prompts data from Turso reactively
    prompts <- reactive({
        turso_query("SELECT date, text FROM prompts ORDER BY date")
    })

    # A reactive expression to return available_dates based on prompts_data
    available_dates <- reactive({
        prompts() %>%
            pull(date) %>%
            unique() %>%
            sort()
    })

    # Render the date input UI
    output$dateInput_ui <- renderUI({
        dateInput(
            "dateInput",
            "Choose a Date",
            value = max(available_dates()),
            min   = min(available_dates()),
            max   = max(available_dates())
        )
    })

    # Reactive expression for selected date
    selected_info <- reactive({

        # Ensure that prompts_data and available_dates have been calculated
        req(prompts(), available_dates())

        selected_date <- input$dateInput
        req(selected_date)  # Ensure that selected_date is not NULL

        # Filter for the selected date
        filtered_data <- prompts() %>%
            filter(date == as.character(selected_date))

        if (nrow(filtered_data) == 0) {
            return(NULL)  # Return NULL if no entries for the selected date
        }

        # Get the prompt text
        selected_prompt <- filtered_data %>%
            slice(1) %>%
            pull(text)

        # Construct R2 URL for the image
        image_filename <- str_glue("gallery-of-the-day-{selected_date}.png")
        selected_image <- str_glue("{R2_PUBLIC_URL}/{image_filename}")

        list(
            prompt = selected_prompt,
            image  = selected_image
        )
    })

    output$imageGallery <- renderUI({

        # Ensure selected_info is available before trying to use it
        req(selected_info())

        # If there's a matching image and caption, display them
        if (length(selected_info()$image) > 0 && length(selected_info()$prompt) > 0) {

            img(
                src   = selected_info()$image,
                class = "gallery-image",
                alt   = "Gallery image"
            )

        } else {

            h5("No image available for this date.")

        }
    })

    output$text_with_breaks <- renderUI({

        # Make sure there is a prompt before trying to display it
        req(selected_info()$prompt)

        # Clean the prompt to get the caption
        selected_caption <- selected_info()$prompt %>%
            clean_and_break_text()

        # Split on newlines and interleave with <br> tags
        lines <- str_split(selected_caption, "\n")[[1]]
        caption_elements <- lapply(lines, function(line) {
            tagList(line, tags$br())
        })

        if (length(selected_info()$image) > 0 && length(selected_info()$prompt) > 0) {
            p(caption_elements)
        } else {
            p("No caption available for this date.")
        }
    })
}
