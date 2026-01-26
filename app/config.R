# Configuration for the Shiny app
# Reads from environment variables set during deployment (secure)
# Falls back to hardcoded values for local development only

R2_PUBLIC_URL <- Sys.getenv("R2_PUBLIC_URL")
if (R2_PUBLIC_URL == "") {
    R2_PUBLIC_URL <- "https://pub-fa8ba5f601374e88994818db80a1c9d2.r2.dev"
}

TURSO_DATABASE_URL <- Sys.getenv("TURSO_DATABASE_URL")
TURSO_AUTH_TOKEN   <- Sys.getenv("TURSO_AUTH_TOKEN")

# For local development, source secret.R if env vars not set
if (TURSO_DATABASE_URL == "" || TURSO_AUTH_TOKEN == "") {
    if (file.exists("../secret.R")) {
        source("../secret.R")
    }
}
