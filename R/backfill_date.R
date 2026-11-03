# Backfill prompt + image for a single past date.
# Usage: Rscript R/backfill_date.R YYYY-MM-DD [--regenerate]
#
# Mirrors create_prompt.R + fetch_image.R but parameterized by date so a gap in
# the daily run can be filled in. Inserts the prompt into Turso and uploads the
# image to R2 under gallery-of-the-day-YYYY-MM-DD.png. Skips work that's already
# done so it's safe to re-run.
#
# With --regenerate the day is made again from scratch (a new event and a new
# image) even though it exists. The new event and image are made first and the
# caption in Turso is updated only after the upload, so a failure leaves the old
# day as it was. Archive the old image and caption before using it.

args <- commandArgs(trailingOnly = TRUE)
if (!length(args) %in% 1:2 || !grepl("^\\d{4}-\\d{2}-\\d{2}$", args[1]) ||
    (length(args) == 2 && args[2] != "--regenerate")) {
    stop("Usage: Rscript R/backfill_date.R YYYY-MM-DD [--regenerate]")
}
target_date <- as.Date(args[1])
target_date_str <- as.character(target_date)
regenerate <- length(args) == 2

OPENAI_API_KEY <- Sys.getenv("OPENAI_API_KEY")
if (OPENAI_API_KEY == "") {
    stop("OPENAI_API_KEY is not set (add it to the environment or .Renviron)")
}

R2_ACCOUNT_ID        <- Sys.getenv("R2_ACCOUNT_ID")
R2_ACCESS_KEY_ID     <- Sys.getenv("R2_ACCESS_KEY_ID")
R2_SECRET_ACCESS_KEY <- Sys.getenv("R2_SECRET_ACCESS_KEY")
R2_BUCKET_NAME       <- Sys.getenv("R2_BUCKET_NAME")

source("R/turso.R")
source("R/config.R")
source("R/wikipedia.R")
source("R/openai.R")
source("R/r2.R")
source("R/daily.R")

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

r2 <- r2_client(R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET_NAME)

# The flow is in R/daily.R
backfill_day(target_date, r2, regenerate = regenerate)
