# Loaded by Shiny once at start, before ui.R and server.R

library(bslib)
library(dplyr)
library(shiny)
library(stringr)

# Settings and text first, then the helpers, then the Turso and R2 configuration
source("www/variables.R")
source("www/strings.R")
source("www/functions.R")
source("www/turso.R")
source("config.R")
