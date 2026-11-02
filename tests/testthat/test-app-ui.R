library(testthat)
library(shiny)
library(bslib)
library(dplyr)
library(stringr)

# ui.R is sourced into its own environment, from the app folder (it reads www/ for the
# asset versions), after the files global.R loads
ui_env <- new.env(parent = globalenv())
for (f in c("variables.R", "strings.R", "functions.R")) {
    source(test_path("../../app/lib", f), local = ui_env)
}
withr::with_dir(test_path("../../app"), source("ui.R", local = ui_env))

# renderTags() returns the <head> content (scripts, stylesheets, inline style) separately
page_html <- function() {
    rendered <- htmltools::renderTags(ui_env$ui)
    paste(rendered$head, rendered$html)
}
footer_links <- function(current) {
    html <- as.character(ui_env$create_app_footer(current))
    m <- regmatches(html, gregexpr('<a href="[^"]+">[^<]+</a>', html))[[1]]
    data.frame(
        url  = sub('<a href="([^"]+)".*', "\\1", m),
        name = sub('.*">([^<]+)</a>', "\\1", m),
        stringsAsFactors = FALSE
    )
}

# The footer ----

test_that("the footer leaves out the current app and links the others", {
    links <- footer_links("gallery")
    apps <- links$name[seq_len(4)]
    expect_equal(apps, c("BiblioStatus", "FillariStatus", "TrackTeller", "TuneTeller"))
    expect_false("Gallery of the Day" %in% links$name)
})

test_that("the footer links every app when no app is excluded", {
    links <- footer_links("")
    expect_true(all(vapply(ui_env$footer_apps, \(app) app$name, character(1)) %in% links$name))
    expect_equal(sum(links$name == "Gallery of the Day"), 1)
})

test_that("an unknown app id excludes nothing", {
    expect_equal(nrow(footer_links("nonsense")), nrow(footer_links("")))
})

test_that("every footer app has its own link, over https", {
    links <- footer_links("gallery")
    app_urls <- links$url[seq_len(4)]
    expect_true(all(startsWith(app_urls, "https://")))
    expect_false(anyDuplicated(app_urls) > 0)
})

test_that("the footer credits the author and the site", {
    html <- as.character(ui_env$create_app_footer("gallery"))
    expect_match(html, ui_env$footer_credit$author_url, fixed = TRUE)
    expect_match(html, ui_env$footer_credit$site_url, fixed = TRUE)
    expect_match(html, "Created by", fixed = TRUE)
})

# The page ----

test_that("the page has the outputs the server fills", {
    html <- page_html()
    for (id in c("imageGallery", "dateInput_ui", "text_with_breaks", "staleNote")) {
        expect_match(html, sprintf('id="%s"', id), fixed = TRUE, info = id)
    }
})

test_that("the stale note sits above the image", {
    html <- page_html()
    expect_lt(regexpr('id="staleNote"', html, fixed = TRUE), regexpr('id="imageGallery"', html, fixed = TRUE))
})

test_that("the page loads its scripts and stylesheet with a version", {
    html <- page_html()
    expect_match(html, 'src="lightbox\\.js\\?v=[0-9]+"')
    expect_match(html, 'src="mode-toggle\\.js\\?v=[0-9]+"')
    expect_match(html, 'href="styles\\.css\\?v=[0-9]+"')
    expect_match(html, "favicon.png", fixed = TRUE)
})

test_that("the page shows the title, the mode switch and the AI disclaimer", {
    html <- page_html()
    expect_match(html, "gallery-title-accent", fixed = TRUE)
    expect_match(html, ui_env$strings$title_accent, fixed = TRUE)
    expect_match(html, 'id="mode-toggle"', fixed = TRUE)
    expect_match(html, "generated with AI", fixed = TRUE)
    expect_match(html, "ai-disclaimer", fixed = TRUE)
})

test_that("the page tells the switch's labels for both modes", {
    html <- page_html()
    expect_match(html, ui_env$strings$mode_to_light, fixed = TRUE)
    expect_match(html, ui_env$strings$mode_to_dark, fixed = TRUE)
})

test_that("asset() adds the file's modification time as the version", {
    v <- withr::with_dir(test_path("../../app"), ui_env$asset("lightbox.js"))
    expect_match(v, "^lightbox\\.js\\?v=[0-9]+$")
    expect_error(withr::with_dir(test_path("../../app"), ui_env$asset("does-not-exist.js")), NA)
})

test_that("the brand colours are in the page", {
    html <- page_html()
    expect_match(html, ui_env$brand_colours$red, ignore.case = TRUE)
    expect_match(html, ui_env$brand_colours$red_on_dark, ignore.case = TRUE)
})
