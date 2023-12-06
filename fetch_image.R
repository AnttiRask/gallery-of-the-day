# Source the secret ----
source("secret.R")

# Load packages ----
library(conflicted)
    conflict_prefer("seq_along", "purrr", "base")
library(httr2)
