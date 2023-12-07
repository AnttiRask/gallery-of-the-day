# Load packages
library(dplyr)
library(readr)
library(shiny)
library(tibble)

server <- function(input, output) {
    
    output$imageGallery <- renderUI({
        
        # Read the prompts data
        prompts        <- read_csv("data/prompts.csv")
        
        # Sort the prompts data to get the latest entry
        prompts_latest <- prompts %>% filter(date == max(date))
        caption_latest <- prompts_latest %>% pull(text)
        
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
            img(src = image_latest, height = "1024px"),
            h5(caption_latest)
        )
    })
}