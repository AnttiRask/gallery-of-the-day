library(shiny)
library(shinydashboard)

ui <- fluidPage(
    
    title = "Gallery of the Day",
    
    tags$head(
        tags$link(
            rel  = "stylesheet",
            type = "text/css",
            href = "styles.css"
        )
    ),
    
    br(),
    
    uiOutput("imageGallery"),
    
    br(),
    br(),
    
    div(class = "date-input-container", uiOutput("dateInput_ui")),
    
    br(),
    
    htmlOutput("text_with_breaks")

)