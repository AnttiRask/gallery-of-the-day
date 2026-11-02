library(testthat)

www <- test_path("../../app/www")

# The public folder ----

test_that("the public www folder holds no R source files", {
    # Everything in www/ is served to anyone; the R code lives in app/lib/ instead
    r_files <- list.files(www, pattern = "\\.R$", ignore.case = TRUE, recursive = TRUE)
    expect_equal(r_files, character(0))
})

test_that("the files the page loads are in the public folder", {
    for (f in c("lightbox.js", "mode-toggle.js", "styles.css", "favicon.png")) {
        expect_true(file.exists(file.path(www, f)), info = f)
    }
})

test_that("the R code folder exists and is not under www", {
    lib <- test_path("../../app/lib")
    expect_true(all(c("variables.R", "strings.R", "functions.R", "data.R", "health.R", "security.R") %in% list.files(lib)))
})

# The JavaScript ----

test_that("the JavaScript files parse", {
    skip_if_not(nzchar(Sys.which("node")), "node is not installed")
    for (f in list.files(www, pattern = "\\.js$", full.names = TRUE)) {
        res <- suppressWarnings(system2("node", c("--check", shQuote(f)), stdout = TRUE, stderr = TRUE))
        expect_null(attr(res, "status"), info = paste(basename(f), paste(res, collapse = " ")))
    }
})

test_that("the lightbox builds its image with DOM calls, not by joining HTML strings", {
    js <- paste(readLines(file.path(www, "lightbox.js"), warn = FALSE), collapse = "\n")
    # The old code concatenated the image's alt text into an HTML string, so a quote in the
    # alt text could add markup. Elements must be created with attributes instead.
    expect_false(grepl("<img\\s", js))                # an <img ...attributes...> string
    expect_false(grepl("alt=\\\\?[\"']\\s*\\+", js))   # alt="' + value
    expect_true(grepl("\\$\\('<img>'", js) || grepl("createElement\\('img'\\)", js))
})

test_that("the mode switch only sets the theme attribute, it doesn't build HTML", {
    js <- paste(readLines(file.path(www, "mode-toggle.js"), warn = FALSE), collapse = "\n")
    expect_match(js, "data-bs-theme", fixed = TRUE)
    expect_false(grepl("innerHTML", js, fixed = TRUE))
})

test_that("the image fallback and the retry button are wired in lightbox.js", {
    js <- paste(readLines(file.path(www, "lightbox.js"), warn = FALSE), collapse = "\n")
    expect_match(js, "data-error-text", fixed = TRUE)
    expect_match(js, "state-retry", fixed = TRUE)
    expect_match(js, "location.reload", fixed = TRUE)
})

# config.R ----

config_env <- function() {
    env <- new.env(parent = globalenv())
    source(test_path("../../app/lib/variables.R"), local = env)
    source(test_path("../../app/config.R"), local = env)
    env
}

test_that("the R2 URL comes from R2_PUBLIC_URL, or falls back to the default", {
    withr::local_envvar(R2_PUBLIC_URL = "https://images.example.com")
    expect_equal(config_env()$R2_PUBLIC_URL, "https://images.example.com")

    withr::local_envvar(R2_PUBLIC_URL = "")
    env <- config_env()
    expect_equal(env$R2_PUBLIC_URL, env$r2_public_url_default)
})

test_that("the Turso settings are read from the environment", {
    withr::local_envvar(TURSO_DATABASE_URL = "libsql://example.turso.io", TURSO_AUTH_TOKEN = "not-a-real-token")
    env <- config_env()
    expect_equal(env$TURSO_DATABASE_URL, "libsql://example.turso.io")
    expect_equal(env$TURSO_AUTH_TOKEN, "not-a-real-token")
})

test_that("missing Turso settings are empty strings, not an error", {
    withr::local_envvar(TURSO_DATABASE_URL = "", TURSO_AUTH_TOKEN = "")
    env <- config_env()
    expect_equal(env$TURSO_DATABASE_URL, "")
    expect_equal(env$TURSO_AUTH_TOKEN, "")
})
