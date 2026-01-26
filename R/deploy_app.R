library(rsconnect)

# Get credentials from environment variables (GitHub Actions) or secret.R (local)
SHINY_APPS_NAME <- Sys.getenv("SHINY_APPS_NAME")
if (SHINY_APPS_NAME == "") {
    source("secret.R")
} else {
    SHINY_APPS_TOKEN     <- Sys.getenv("SHINY_APPS_TOKEN")
    SHINY_APPS_SECRET    <- Sys.getenv("SHINY_APPS_SECRET")
    R2_PUBLIC_URL        <- Sys.getenv("R2_PUBLIC_URL")
    TURSO_DATABASE_URL   <- Sys.getenv("TURSO_DATABASE_URL")
    TURSO_AUTH_TOKEN     <- Sys.getenv("TURSO_AUTH_TOKEN")
}

setAccountInfo(
    name   = SHINY_APPS_NAME,
    token  = SHINY_APPS_TOKEN,
    secret = SHINY_APPS_SECRET
)

# Set environment variables that will be deployed to ShinyApps.io
# rsconnect reads these from the current environment
Sys.setenv(
    R2_PUBLIC_URL      = R2_PUBLIC_URL,
    TURSO_DATABASE_URL = TURSO_DATABASE_URL,
    TURSO_AUTH_TOKEN   = TURSO_AUTH_TOKEN
)

# Deploy the app with environment variables
# envVars takes just the names of env vars to include
deployApp(
    appDir      = "app/",
    appName     = "gallery-of-the-day",
    account     = "youcanbeapirate",
    forceUpdate = TRUE,
    envVars     = c("R2_PUBLIC_URL", "TURSO_DATABASE_URL", "TURSO_AUTH_TOKEN")
)
