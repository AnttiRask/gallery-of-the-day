library(shiny)

# The R files live in lib/, which Shiny doesn't serve (only www/ is public)
source("app/lib/variables.R")
source("app/lib/security.R")
source("app/lib/health.R")
# Run from the app directory so ui.R / server.R find their www/ files
setwd("app")

port <- as.integer(Sys.getenv("PORT", "8080"))
# The health check sits inside the security wrapper, so its answer gets the headers
app <- with_security_headers(with_health_check(shinyAppDir(".")))
runApp(app, host = "0.0.0.0", port = port)
