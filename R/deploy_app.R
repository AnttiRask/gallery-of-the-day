library(rsconnect)

# Get credentials from environment variables (GitHub Actions) or secret.R (local)
SHINY_APPS_NAME <- Sys.getenv("SHINY_APPS_NAME")
if (SHINY_APPS_NAME == "") {
    source("secret.R")
} else {
    SHINY_APPS_TOKEN  <- Sys.getenv("SHINY_APPS_TOKEN")
    SHINY_APPS_SECRET <- Sys.getenv("SHINY_APPS_SECRET")
}

setAccountInfo(
    name   = SHINY_APPS_NAME,
    token  = SHINY_APPS_TOKEN,
    secret = SHINY_APPS_SECRET
)

# Deploy the app
# Environment variables are set via .Renviron file (created by GitHub Actions)
deployApp(
    appDir      = "app/",
    appName     = "gallery-of-the-day",
    account     = "youcanbeapirate",
    forceUpdate = TRUE
)
