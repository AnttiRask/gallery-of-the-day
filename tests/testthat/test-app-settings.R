library(testthat)

source(test_path("../../app/www/variables.R"))
source(test_path("../../app/www/strings.R"))

test_that("the footer lists each app once, over https, and includes this one", {
    ids <- vapply(footer_apps, \(app) app$id, character(1))
    urls <- vapply(footer_apps, \(app) app$url, character(1))
    expect_false(anyDuplicated(ids) > 0)
    expect_true("gallery" %in% ids)
    expect_true(all(grepl("^https://", urls)))
    expect_true("fillaristatus" %in% ids)
})

test_that("every footer entry has an id, a name and a url", {
    expect_true(all(vapply(footer_apps, \(app) all(c("id", "name", "url") %in% names(app)), logical(1))))
})

test_that("the brand colours are hex codes", {
    expect_true(all(grepl("^#[0-9A-Fa-f]{6}$", unlist(brand_colours))))
})

test_that("the strings the page needs are all there and are plain text", {
    needed <- c("app_title", "title_accent", "title_rest", "date_label", "date_aria",
                "mode_to_light", "mode_to_dark", "no_image", "no_caption", "disclaimer")
    expect_true(all(needed %in% names(strings)))
    expect_true(all(vapply(strings, is.character, logical(1))))
    # no markup: the page builds its HTML with tags, never from these strings
    expect_false(any(grepl("<[a-z]", unlist(strings))))
})
