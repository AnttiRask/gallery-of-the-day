# Configuration for the Shiny app
# Reads from environment variables set during deployment (secure)
# Falls back to hardcoded values for local development only

source("www/variables.R")

R2_PUBLIC_URL <- Sys.getenv("R2_PUBLIC_URL")
if (R2_PUBLIC_URL == "") {
    R2_PUBLIC_URL <- r2_public_url_default
}

TURSO_DATABASE_URL <- Sys.getenv("TURSO_DATABASE_URL")
TURSO_AUTH_TOKEN   <- Sys.getenv("TURSO_AUTH_TOKEN")
