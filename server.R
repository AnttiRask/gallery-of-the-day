# Source functions
source("www/functions.R")

# Load packages
library(dplyr)
library(readr)
library(shiny)
library(stringr)
library(tibble)

server <- function(input, output) {
    
    output$imageGallery <- renderUI({
        
        # Get a list of image files sorted by modified time
        image_files    <- list.files(path = "img/", full.names = TRUE)
        image_latest   <- image_files %>%
            enframe(name = NULL, value = "filepath") %>%
            mutate(mtime = file.info(filepath)$mtime) %>%
            slice_max(mtime) %>%
            pull(filepath)
        
        # Display the latest image and caption
        addResourcePath("img", "img/")
        
        tagList(
            
            div(
                class = "title",
                h1("Gallery of the Day")
            ),
            
            br(),
            
            img(
                src    = image_latest,
                class  = "img-responsive",
                alt    = "Gallery image",
                height = "1024px",
                width  = "1024px"
            )
        )
    })
    
    output$text_with_breaks <- renderUI({
        
        # Read the prompts data
        prompts        <- read_csv("data/prompts.csv")
        
        # Sort the prompts data to get the latest entry
        prompts_latest <- prompts %>%
            filter(date == max(date))
        
        # Clean the prompt to get the caption
        caption_latest <- prompts_latest %>%
            pull(text) %>%
            clean_and_break_text()
        
        # Replace newline characters with HTML line breaks
        caption_with_breaks <- HTML(str_replace_all(caption_latest, "\n", "<br>"))

        tagList(
            div(
                class = "caption",
                h5(caption_with_breaks)
            )
        )
    })
}