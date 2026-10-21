# Loaded by Shiny once at start, before ui.R and server.R

library(bslib)
library(dplyr)
library(shiny)
library(stringr)

# Show visitors a generic message for any error not handled in the app; the real
# error still goes to the log
options(shiny.sanitize.errors = TRUE)

# Settings and text first, then the helpers, then the Turso and R2 configuration
source("www/variables.R")
source("www/strings.R")
source("www/functions.R")
# The Turso helpers are shared with the daily scripts (the Dockerfile copies the file)
source("../R/turso.R")
source("www/data.R")
source("config.R")

# Fill the prompts cache once the app is up, so the first visitor doesn't wait for
# Turso. Failure is harmless: load_prompts() never throws and the first session retries.
later::later(function() invisible(load_prompts()), delay = 1)
