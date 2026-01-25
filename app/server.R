# Source functions and config
source("www/functions.R")
source("config.R")

# Load packages
library(dplyr)
library(readr)
library(shiny)
library(stringr)
library(tibble)

server <- function(input, output, session) {
    
    # Read the prompts data reactively
    prompts         <- reactive({
        read_csv("data/prompts.csv")
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
            filter(date == selected_date)
        
        if (nrow(filtered_data) == 0) {
            return(NULL)  # Return NULL if no entries for the selected date
        }
        
        # Filter for the selected date
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
            
            tagList(
                
                div(
                    class = "title",
                    h1("Gallery of the Day")
                ),
                
                br(),
                
                img(
                    src    = selected_info()$image,
                    class  = "img-responsive",
                    alt    = "Gallery image",
                    height = "1024px",
                    width  = "1024px"
                )
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
        
        # Replace newline characters with HTML line breaks
        caption_with_breaks <- HTML(str_replace_all(selected_caption, "\n", "<br>"))
        
        # If there's a matching image and caption, display them
        if (length(selected_info()$image) > 0 && length(selected_info()$prompt) > 0) {
            
            tagList(
                div(
                    class = "caption",
                    h5(caption_with_breaks)
                )
            )
            
        } else {
            
            h5("No caption available for this date.")
            
        }
    })
}