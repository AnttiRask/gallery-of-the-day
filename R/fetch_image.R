# Get API key from the environment (GitHub Actions secret, or .Renviron locally)
OPENAI_API_KEY <- Sys.getenv("OPENAI_API_KEY")
if (OPENAI_API_KEY == "") {
    stop("OPENAI_API_KEY is not set (add it to the environment or .Renviron)")
}

# Get R2 credentials from the environment
R2_ACCOUNT_ID        <- Sys.getenv("R2_ACCOUNT_ID")
R2_ACCESS_KEY_ID     <- Sys.getenv("R2_ACCESS_KEY_ID")
R2_SECRET_ACCESS_KEY <- Sys.getenv("R2_SECRET_ACCESS_KEY")
R2_BUCKET_NAME       <- Sys.getenv("R2_BUCKET_NAME")

# Load Turso helper functions and the shared settings and OpenAI helpers
source("R/turso.R")
source("R/config.R")
source("R/wikipedia.R")
source("R/openai.R")
source("R/r2.R")
source("R/daily.R")

# Load packages ----
library(conflicted)
    conflicts_prefer(dplyr::filter)
library(aws.s3)
library(curl)
library(dplyr)
library(httr2)
library(jsonlite)
library(lubridate)
library(purrr)
library(stringr)

# Today's image, unless it already exists in R2 (the flow is in R/daily.R) ----
r2 <- r2_client(R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET_NAME)

fetch_daily_image(today(), r2)
