# Get API key from the environment (GitHub Actions secret, or .Renviron locally)
OPENAI_API_KEY <- Sys.getenv("OPENAI_API_KEY")
if (OPENAI_API_KEY == "") {
    stop("OPENAI_API_KEY is not set (add it to the environment or .Renviron)")
}

# Load Turso helper functions and the shared settings and OpenAI helpers
source("R/turso.R")
source("R/config.R")
source("R/wikipedia.R")
source("R/openai.R")
source("R/daily.R")

# Load packages ----
library(dplyr)
library(httr2)
library(jsonlite)
library(lubridate)
library(purrr)
library(stringr)

# Today's prompt, unless it already exists in Turso (the flow is in R/daily.R) ----
create_daily_prompt(today())
