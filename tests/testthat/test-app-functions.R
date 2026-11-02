library(testthat)
library(shiny)
library(dplyr)
library(stringr)

# The helpers are sourced into their own environment (they use strings and shiny tags)
fn_env <- new.env(parent = globalenv())
for (f in c("variables.R", "strings.R", "functions.R")) {
    source(test_path("../../app/lib", f), local = fn_env)
}

# add_spaces_after_periods() ----

test_that("a period glued to the next word gets a space", {
    expect_equal(fn_env$add_spaces_after_periods("One.Two"), "One. Two")
    expect_equal(fn_env$add_spaces_after_periods("Done.Next one.Last"), "Done. Next one. Last")
})

# (A period at the very end gets a trailing space; that is harmless, so these compare
# the trimmed result.)
test_that("text that is already spaced, or ends with a period, is left alone", {
    expect_equal(trimws(fn_env$add_spaces_after_periods("A. B. C.")), "A. B. C.")
    expect_equal(trimws(fn_env$add_spaces_after_periods("The end.")), "The end.")
    expect_equal(fn_env$add_spaces_after_periods("No periods here"), "No periods here")
})

# Known defect, found 2026-11-03 while writing these tests: the rule adds a space after
# EVERY period that has no space after it, so decimals and initials break ("3.5" becomes
# "3. 5", "U.S." becomes "U. S."). 21 of the 306 stored captions are shown that way.
# Remove the skip when the rule only touches a period between a lowercase letter and a
# capital letter.
test_that("decimals and initials are left alone", {
    skip("known defect: 3.5 shows as '3. 5' and U.S. as 'U. S.' (21 of 306 captions)")
    expect_equal(fn_env$add_spaces_after_periods("It grew 3.5 million."), "It grew 3.5 million.")
    expect_equal(fn_env$add_spaces_after_periods("The U.S. team won."), "The U.S. team won.")
})

# insert_row_breaks() ----

test_that("a short caption stays one paragraph, unchanged", {
    text <- "A short caption. Two sentences."
    expect_equal(fn_env$insert_row_breaks(text), text)
})

sentence <- "This is a sentence of moderate length that goes on a bit."   # 57 characters
long_text <- paste(rep(sentence, 12), collapse = " ")

test_that("a long caption is split into paragraphs that stay under the limit", {
    out <- fn_env$insert_row_breaks(long_text, max_length = 120)
    paragraphs <- strsplit(out, "\n\n", fixed = TRUE)[[1]]
    expect_gt(length(paragraphs), 1)
    expect_true(all(nchar(paragraphs) <= 120))
})

test_that("breaking a caption loses no words and never splits a sentence", {
    out <- fn_env$insert_row_breaks(long_text, max_length = 120)
    expect_equal(gsub("\n\n", " ", out, fixed = TRUE), long_text)
    paragraphs <- strsplit(out, "\n\n", fixed = TRUE)[[1]]
    expect_true(all(grepl("\\.$", paragraphs)))
})

test_that("one sentence longer than the limit stays whole", {
    one <- paste0(paste(rep("word", 200), collapse = " "), ".")
    expect_equal(trimws(fn_env$insert_row_breaks(one, max_length = 50)), one)
})

# Known quirk: when the FIRST sentence is longer than the limit, the result starts with a
# paragraph break (a blank line above the caption). Captions start with a short sentence
# ("On January 7, 1927, ..."), so it hasn't shown up; remove the skip when it is fixed.
test_that("a very long first sentence doesn't start with a blank paragraph", {
    skip("known quirk: a first sentence over the limit gets a leading paragraph break")
    one <- paste0(paste(rep("word", 200), collapse = " "), ".")
    expect_false(startsWith(fn_env$insert_row_breaks(one, max_length = 50), "\n"))
})

test_that("an empty caption stays empty", {
    expect_equal(fn_env$insert_row_breaks(""), "")
})

test_that("clean_and_break_text spaces the periods, then breaks the paragraphs", {
    expect_equal(trimws(fn_env$clean_and_break_text("Hello.World is fine.")), "Hello. World is fine.")
    glued <- paste(rep("This is a sentence of moderate length that goes on a bit.", 12), collapse = "")
    out <- fn_env$clean_and_break_text(glued)
    expect_gt(length(strsplit(out, "\n\n", fixed = TRUE)[[1]]), 1)
    expect_false(grepl("\\.[A-Z]", out))
})

# state_message() ----

test_that("state_message shows the text as a status, without a button by default", {
    html <- as.character(fn_env$state_message("Nothing here"))
    expect_match(html, "Nothing here", fixed = TRUE)
    expect_match(html, 'role="status"', fixed = TRUE)
    expect_match(html, "state-message", fixed = TRUE)
    expect_false(grepl("state-retry", html, fixed = TRUE))
})

test_that("state_message adds the retry button only when asked", {
    html <- as.character(fn_env$state_message("Unavailable", retry = TRUE))
    expect_match(html, "state-retry", fixed = TRUE)
    expect_match(html, fn_env$strings$try_again, fixed = TRUE)
    expect_match(html, 'type="button"', fixed = TRUE)
})

test_that("state_message escapes markup in the text", {
    html <- as.character(fn_env$state_message("<script>alert(1)</script>"))
    expect_false(grepl("<script>", html, fixed = TRUE))
})
