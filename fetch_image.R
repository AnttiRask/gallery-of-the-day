# # Source the secret ----
# source("secret.R")

# Load packages ----
library(conflicted)
    conflicts_prefer(dplyr::filter)
library(dplyr)
library(httr2)
library(lubridate)
library(purrr)
library(readr)
library(stringr)

# Create the API POST request ----

## Insert the arguments ----

# Model
model   <- "dall-e-3"

# The text prompt
prompts <- read_csv("data/prompts.csv")
prompt  <- prompts %>%
    filter(date == max(date)) %>%
    pull(text)

# The number of images
n       <- 1

# Image size
size    <- "1024x1024"

## Create the request ----

# The URL for this particular use case (see documentation for others)
url <- "https://api.openai.com/v1/images/generations"

# Gather the arguments as the body of the request
body    <- list(
    model  = model,
    prompt = prompt,
    n      = n,
    size   = size
)

# For the request you need to replace the OPENAI_API_KEY with your own API key
# that you get after signing up: https://platform.openai.com/account/api-keys
request <- request(url) %>%
    req_headers(Authorization = str_glue("Bearer {OPENAI_API_KEY}")) %>%
    req_body_json(body) %>%
    req_perform()

# Check the request was successful (status code should be 200) ----
request$status_code

# Let's take a look at the content ----
request %>%
    resp_body_json() %>% 
    glimpse()

# Save the image URL ----
url_img <- request %>%
    resp_body_json() %>%
    pluck("data") %>%
    unlist() %>%
    pluck("url")

# Download the image ----

# Create the destination file name
destfile <- str_glue("img/gallery-of-the-day-{today()}.png")

# Download the file at the URLand save it to 'destfile'
download.file(url_img, destfile, mode = "wb")
