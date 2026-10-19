## Security headers for the HTML page.
##
## Shiny has no built-in hook for response headers (the `shiny.http.response.filter`
## option does nothing), so run.R wraps the app's page handler instead. Static
## assets are served by other handlers and don't need these headers.
##
## Needs www/variables.R (sourced by run.R first).

# The images come from the R2 bucket, from the same setting the app builds its
# image URLs from (config.R), so the two can't drift apart. Only the origin
# (https://host) goes into the policy.
r2_public_url <- function() {
    url <- Sys.getenv("R2_PUBLIC_URL")
    if (url == "") r2_public_url_default else url
}

image_host <- function(url = r2_public_url()) {
    if (!grepl("^https://[A-Za-z0-9.-]+(:[0-9]+)?(/|$)", url)) {
        # A bad value would block every image, so refuse to start: Cloud Run then
        # keeps serving the previous revision
        stop("R2_PUBLIC_URL must be an https:// URL, got: ", url)
    }
    sub("^(https://[^/]+).*$", "\\1", url)
}

font_host <- "https://fonts.cdnfonts.com"

# The policy, enforced. Shiny and bslib use inline scripts and styles, hence
# 'unsafe-inline'; wss: is the Shiny websocket. 'unsafe-eval' is not allowed:
# nothing in the app needs it (checked in the browser in both colour modes).
# frame-ancestors is the modern clickjacking protection (X-Frame-Options below
# is the fallback).
content_security_policy <- function(images = image_host()) {
    paste(
        "default-src 'self'",
        "script-src 'self' 'unsafe-inline'",
        paste("style-src 'self' 'unsafe-inline'", font_host),
        paste("font-src 'self' data:", font_host),
        paste("img-src 'self' data: blob:", images),
        "connect-src 'self' wss:",
        "frame-ancestors 'none'",
        "base-uri 'self'",
        "object-src 'none'",
        "form-action 'self'",
        sep = "; "
    )
}

security_headers <- function() {
    list(
        "Content-Security-Policy"   = content_security_policy(),
        "X-Frame-Options"           = "DENY",
        "X-Content-Type-Options"    = "nosniff",
        "Referrer-Policy"           = "strict-origin-when-cross-origin",
        # The app needs no device features
        "Permissions-Policy"        = "geolocation=(), camera=(), microphone=(), payment=(), usb=()",
        # Cloud Run only serves HTTPS; one year, no subdomains, no preload
        "Strict-Transport-Security" = "max-age=31536000"
    )
}

add_headers <- function(response, headers) {
    if (inherits(response, "httpResponse")) {
        for (name in names(headers)) {
            response$headers[[name]] <- headers[[name]]
        }
    }
    response
}

# Wrap a Shiny app object so every page response carries the headers. Handles
# the three things a handler can return: NULL, a response, or a promise.
with_security_headers <- function(app, headers = security_headers()) {
    original <- app$httpHandler
    app$httpHandler <- function(req) {
        res <- original(req)
        if (promises::is.promising(res)) {
            promises::then(res, function(value) add_headers(value, headers))
        } else {
            add_headers(res, headers)
        }
    }
    app
}
