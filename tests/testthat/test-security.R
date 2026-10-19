library(testthat)

source(test_path("../../app/www/variables.R"))
source(test_path("../../app/www/security.R"))

test_that("the header set covers framing, referrers, permissions, transport and CSP", {
    h <- security_headers()
    expect_equal(h[["X-Frame-Options"]], "DENY")
    expect_equal(h[["X-Content-Type-Options"]], "nosniff")
    expect_equal(h[["Referrer-Policy"]], "strict-origin-when-cross-origin")
    expect_match(h[["Strict-Transport-Security"]], "^max-age=[0-9]+$")
    expect_false(grepl("includeSubDomains|preload", h[["Strict-Transport-Security"]]))
    expect_match(h[["Permissions-Policy"]], "geolocation=()", fixed = TRUE)
    expect_match(h[["Permissions-Policy"]], "camera=()", fixed = TRUE)
})

test_that("the CSP is enforced, not report-only", {
    h <- security_headers()
    expect_true("Content-Security-Policy" %in% names(h))
    expect_false("Content-Security-Policy-Report-Only" %in% names(h))
})

test_that("the CSP blocks everything by default and keeps the anti-framing directives", {
    csp <- security_headers()[["Content-Security-Policy"]]
    expect_match(csp, "default-src 'self'", fixed = TRUE)
    expect_match(csp, "frame-ancestors 'none'", fixed = TRUE)
    expect_match(csp, "object-src 'none'", fixed = TRUE)
    expect_match(csp, "base-uri 'self'", fixed = TRUE)
    expect_match(csp, "form-action 'self'", fixed = TRUE)
})

test_that("the CSP allows exactly the hosts the app uses", {
    withr::local_envvar(R2_PUBLIC_URL = "")
    csp <- content_security_policy()
    # the R2 bucket the images come from (the default when the variable is not set)
    expect_match(csp, "img-src [^;]*https://pub-fa8ba5f601374e88994818db80a1c9d2\\.r2\\.dev")
    expect_match(csp, "font-src [^;]*https://fonts\\.cdnfonts\\.com")
    expect_match(csp, "style-src [^;]*https://fonts\\.cdnfonts\\.com")
    expect_match(csp, "connect-src 'self' wss:", fixed = TRUE)
    # nothing is allowed from arbitrary hosts: no bare * and no bare https:
    expect_false(grepl("(^|[; ])\\*([; ]|$)|https:(;| |$)", csp))
})

test_that("the CSP doesn't allow eval, and only allows inline script and style", {
    csp <- security_headers()[["Content-Security-Policy"]]
    expect_false(grepl("unsafe-eval", csp, fixed = TRUE))
    expect_match(csp, "script-src 'self' 'unsafe-inline'(;|$)")
    expect_match(csp, "style-src 'self' 'unsafe-inline' https://fonts\\.cdnfonts\\.com")
})

# The image host follows the same setting as the app's image URLs ----

test_that("the image host is the origin of R2_PUBLIC_URL, or the default", {
    withr::local_envvar(R2_PUBLIC_URL = "")
    expect_equal(image_host(), "https://pub-fa8ba5f601374e88994818db80a1c9d2.r2.dev")

    withr::local_envvar(R2_PUBLIC_URL = "https://images.example.com/some/path/")
    expect_equal(image_host(), "https://images.example.com")
    expect_match(content_security_policy(), "img-src 'self' data: blob: https://images.example.com;", fixed = TRUE)

    withr::local_envvar(R2_PUBLIC_URL = "https://images.example.com:8443")
    expect_equal(image_host(), "https://images.example.com:8443")
})

test_that("a bad R2_PUBLIC_URL stops the start instead of silently blocking every image", {
    expect_error(image_host("http://images.example.com"), "must be an https:// URL")
    expect_error(image_host("not a url"), "must be an https:// URL")
    expect_error(image_host("https://"), "must be an https:// URL")
    # a URL with a space or a quote could otherwise end up in the policy header
    expect_error(image_host("https://x.com; script-src *"), "must be an https:// URL")
})

# The handler wrapper ----

fake_app <- function(handler) structure(list(httpHandler = handler), class = "shiny.appobj")

test_that("with_security_headers adds headers to page responses", {
    app <- with_security_headers(fake_app(function(req) {
        shiny::httpResponse(200, "text/html", "<p>hi</p>", headers = list("X-Existing" = "kept"))
    }))
    res <- app$httpHandler(list(PATH_INFO = "/"))
    expect_s3_class(res, "httpResponse")
    expect_equal(res$headers[["X-Frame-Options"]], "DENY")
    expect_equal(res$headers[["X-Existing"]], "kept")
    expect_equal(res$content, "<p>hi</p>")
})

test_that("with_security_headers leaves NULL responses alone", {
    app <- with_security_headers(fake_app(function(req) NULL))
    expect_null(app$httpHandler(list(PATH_INFO = "/other")))
})

test_that("with_security_headers also covers promised responses", {
    app <- with_security_headers(fake_app(function(req) {
        promises::promise_resolve(shiny::httpResponse(200, "text/html", "<p>later</p>"))
    }))
    res <- NULL
    promises::then(app$httpHandler(list(PATH_INFO = "/")), function(value) res <<- value)
    while (is.null(res)) later::run_now(0.1)
    expect_equal(res$headers[["X-Content-Type-Options"]], "nosniff")
    expect_equal(res$content, "<p>later</p>")
})
