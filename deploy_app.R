library(rsconnect)

setAccountInfo(
    name   = Sys.getenv("SHINY_APPS_NAME"),
    token  = Sys.getenv("SHINY_APPS_TOKEN"),
    secret = Sys.getenv("SHINY_APPS_SECRET")
)

deployApp()