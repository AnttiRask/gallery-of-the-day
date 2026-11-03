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

test_that("a period that ends a sentence, glued to the next one, gets a space", {
    expect_equal(fn_env$add_spaces_after_periods("One.Two"), "One. Two")
    expect_equal(fn_env$add_spaces_after_periods("Done.Next one.Last"), "Done. Next one. Last")
    expect_equal(fn_env$add_spaces_after_periods("It ended in 1927.The next year"), "It ended in 1927. The next year")
    expect_equal(fn_env$add_spaces_after_periods("(see above).Then"), "(see above). Then")
    expect_equal(fn_env$add_spaces_after_periods("Dr.Smith"), "Dr. Smith")
})

test_that("a period glued to a bold heading gets a space, whatever comes before it", {
    expect_equal(
        fn_env$add_spaces_after_periods("the Iberian Peninsula.**Setting and Atmosphere:** The"),
        "the Iberian Peninsula. **Setting and Atmosphere:** The"
    )
    expect_equal(fn_env$add_spaces_after_periods("World War II.**Setting:** The"), "World War II. **Setting:** The")
})

test_that("text that is already spaced, or ends with a period, is left exactly as it is", {
    expect_equal(fn_env$add_spaces_after_periods("A. B. C."), "A. B. C.")
    expect_equal(fn_env$add_spaces_after_periods("The end."), "The end.")
    expect_equal(fn_env$add_spaces_after_periods("No periods here"), "No periods here")
    expect_equal(fn_env$add_spaces_after_periods(""), "")
})

# Found 2026-11-03: the first version added a space after EVERY period without one, so
# decimals and initials broke ("3.5" showed as "3. 5", "U.S." as "U. S."): 21 of the 306
# stored captions.
test_that("decimals are left alone", {
    expect_equal(fn_env$add_spaces_after_periods("It grew 3.5 million."), "It grew 3.5 million.")
    expect_equal(fn_env$add_spaces_after_periods("A 12.75% rise, version 2.0"), "A 12.75% rise, version 2.0")
})

test_that("initials and abbreviations in capitals are left alone", {
    expect_equal(fn_env$add_spaces_after_periods("The U.S. team won."), "The U.S. team won.")
    expect_equal(fn_env$add_spaces_after_periods("In Washington, D.C., it rained."), "In Washington, D.C., it rained.")
    expect_equal(fn_env$add_spaces_after_periods("The U.S.A. flag"), "The U.S.A. flag")
})

test_that("domain names are left alone", {
    expect_equal(fn_env$add_spaces_after_periods("see example.com for more"), "see example.com for more")
})

test_that("a period before a closing quote or a comma gets no stray space", {
    expect_equal(fn_env$add_spaces_after_periods('He said "stop." Then left.'), 'He said "stop." Then left.')
    expect_equal(fn_env$add_spaces_after_periods("the \u201cfirst.\u201d Then"), "the \u201cfirst.\u201d Then")
    expect_equal(fn_env$add_spaces_after_periods("approx., about"), "approx., about")
})

test_that("it works on a vector of captions", {
    expect_equal(fn_env$add_spaces_after_periods(c("a.B", "3.5", NA)), c("a. B", "3.5", NA))
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

# A first sentence longer than the limit used to leave a blank paragraph above the caption
test_that("a very long first sentence doesn't start with a blank paragraph", {
    one <- paste0(paste(rep("word", 200), collapse = " "), ".")
    expect_false(startsWith(fn_env$insert_row_breaks(one, max_length = 50), "\n"))
    expect_equal(fn_env$insert_row_breaks(one, max_length = 50), one)
    out <- fn_env$insert_row_breaks(paste(one, "Short next one."), max_length = 50)
    expect_equal(out, paste0(one, "\n\nShort next one."))
})

test_that("an empty caption stays empty", {
    expect_equal(fn_env$insert_row_breaks(""), "")
})

test_that("clean_and_break_text spaces the periods, then breaks the paragraphs", {
    expect_equal(fn_env$clean_and_break_text("Hello.World is fine."), "Hello. World is fine.")
    expect_equal(fn_env$clean_and_break_text("The U.S. grew 3.5 percent."), "The U.S. grew 3.5 percent.")
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
