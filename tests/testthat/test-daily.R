library(testthat)

source("../../R/config.R")
source("../../R/wikipedia.R")
source("../../R/openai.R")
source("../../R/r2.R")
source("../../R/daily.R")

# Fakes: every call is logged in order, so the tests can check what was written and when ----

day <- as.Date("2026-11-03")
png <- as.raw(c(0x89, 0x50, 0x4e, 0x47))

new_log <- function() {
    log <- new.env()
    log$calls <- list()
    log$add <- function(what, ...) log$calls[[length(log$calls) + 1]] <- list(what = what, ...)
    log$whats <- function() vapply(log$calls, \(x) x$what, "")
    log
}

# A fake Turso: `rows` is what a SELECT of the text returns (NULL = no row), and
# the COUNT query answers with the number of rows
fake_query <- function(log, text = NULL) {
    function(sql, params = list()) {
        log$add("query", sql = sql, params = params)
        if (grepl("COUNT", sql)) return(data.frame(count = if (is.null(text)) 0L else 1L))
        data.frame(text = text %||% character())
    }
}
fake_execute <- function(log) {
    function(sql, params = list()) log$add("execute", sql = sql, params = params)
}
fake_r2 <- function(log, exists = FALSE) {
    list(
        exists = function(key) { log$add("r2_exists", key = key); exists },
        upload = function(image, key) log$add("r2_upload", key = key, image = image)
    )
}
fake_event <- function(log, caption = "A caption about a happy day.") {
    function(date) {
        log$add("generate_event", date = date)
        list(year = 1969L, event = "Something happened.", caption = caption)
    }
}
fake_image <- function(log, caption = NULL, changed = FALSE, fail = FALSE) {
    function(prompt, date) {
        log$add("generate_image", prompt = prompt)
        if (fail) stop("image failed")
        list(image = png, caption = caption %||% prompt, changed = changed)
    }
}
quiet <- function(code) { capture.output(value <- force(code)); value }

# create_daily_prompt ----

test_that("a day that already has a prompt is skipped without a model call or a write", {
    log <- new_log()
    result <- quiet(create_daily_prompt(day, fake_query(log, "old"), fake_execute(log), fake_event(log)))
    expect_equal(result, "skipped")
    expect_equal(log$whats(), "query")
})

test_that("a new day gets its caption inserted with the date as text", {
    log <- new_log()
    result <- quiet(create_daily_prompt(day, fake_query(log), fake_execute(log), fake_event(log, "Caption!")))
    expect_equal(result, "created")
    expect_equal(log$whats(), c("query", "generate_event", "execute"))
    insert <- log$calls[[3]]
    expect_match(insert$sql, "INSERT INTO prompts")
    expect_equal(insert$params, list("Caption!", "2026-11-03"))
    expect_equal(log$calls[[1]]$params, list("2026-11-03"))
})

test_that("a model failure writes nothing", {
    log <- new_log()
    boom <- function(date) stop("model failed")
    expect_error(quiet(create_daily_prompt(day, fake_query(log), fake_execute(log), boom)), "model failed")
    expect_equal(log$whats(), "query")
})

test_that("a failed insert is an error, not a silent success", {
    log <- new_log()
    execute <- function(sql, params = list()) stop("Turso down")
    expect_error(quiet(create_daily_prompt(day, fake_query(log), execute, fake_event(log))), "Turso down")
})

# fetch_daily_image ----

test_that("an image that is already in R2 is skipped before anything else", {
    log <- new_log()
    result <- quiet(fetch_daily_image(day, fake_r2(log, exists = TRUE), fake_query(log, "x"), fake_execute(log), fake_image(log)))
    expect_equal(result, "skipped")
    expect_equal(log$whats(), "r2_exists")
    expect_equal(log$calls[[1]]$key, "gallery-of-the-day-2026-11-03.png")
})

test_that("a missing, empty or NA prompt stops the run with a clear message and no model call", {
    for (text in list(NULL, "", NA_character_)) {
        log <- new_log()
        query <- function(sql, params = list()) {
            if (is.null(text)) data.frame(text = character()) else data.frame(text = text)
        }
        expect_error(
            quiet(fetch_daily_image(day, fake_r2(log), query, fake_execute(log), fake_image(log))),
            "There is no prompt for 2026-11-03 in Turso"
        )
        expect_false("generate_image" %in% log$whats())
    }
})

test_that("a new image is made from the stored prompt and uploaded under the day's key", {
    log <- new_log()
    result <- quiet(fetch_daily_image(day, fake_r2(log), fake_query(log, "Stored caption"), fake_execute(log), fake_image(log)))
    expect_equal(result, "uploaded")
    expect_equal(log$whats(), c("r2_exists", "query", "generate_image", "r2_upload"))
    expect_equal(log$calls[[3]]$prompt, "Stored caption")
    expect_equal(log$calls[[4]]$key, "gallery-of-the-day-2026-11-03.png")
    expect_identical(log$calls[[4]]$image, png)
})

test_that("a caption the safety system changed goes to Turso before the upload", {
    log <- new_log()
    quiet(fetch_daily_image(
        day, fake_r2(log), fake_query(log, "Original"), fake_execute(log),
        fake_image(log, caption = "Rewritten", changed = TRUE)
    ))
    expect_equal(log$whats(), c("r2_exists", "query", "generate_image", "execute", "r2_upload"))
    update <- log$calls[[4]]
    expect_match(update$sql, "UPDATE prompts SET text")
    expect_equal(update$params, list("Rewritten", "2026-11-03"))
})

test_that("an image failure writes and uploads nothing; an upload failure is an error", {
    log <- new_log()
    expect_error(
        quiet(fetch_daily_image(day, fake_r2(log), fake_query(log, "x"), fake_execute(log), fake_image(log, fail = TRUE))),
        "image failed"
    )
    expect_false(any(c("execute", "r2_upload") %in% log$whats()))

    r2 <- fake_r2(new_log())
    r2$upload <- function(image, key) stop("Failed to upload image to R2")
    expect_error(
        quiet(fetch_daily_image(day, r2, fake_query(new_log(), "x"), fake_execute(new_log()), fake_image(new_log()))),
        "Failed to upload"
    )
})

# backfill_day ----

test_that("a day with a prompt and an image is left alone", {
    log <- new_log()
    result <- quiet(backfill_day(day, fake_r2(log, exists = TRUE), FALSE, fake_query(log, "Have it"), fake_execute(log), fake_event(log), fake_image(log)))
    expect_equal(result, "complete")
    expect_false(any(c("execute", "generate_event", "generate_image", "r2_upload") %in% log$whats()))
})

test_that("a day with a prompt but no image reuses the prompt and only makes the image", {
    log <- new_log()
    result <- quiet(backfill_day(day, fake_r2(log), FALSE, fake_query(log, "Have it"), fake_execute(log), fake_event(log), fake_image(log)))
    expect_equal(result, "backfilled")
    expect_false(any(c("execute", "generate_event") %in% log$whats()))
    expect_equal(log$calls[[which(log$whats() == "generate_image")]]$prompt, "Have it")
    expect_true("r2_upload" %in% log$whats())
})

test_that("a day with nothing gets a caption inserted, then its image", {
    log <- new_log()
    query <- function(sql, params = list()) {
        log$add("query", sql = sql)
        if (grepl("COUNT", sql)) data.frame(count = 0L) else data.frame(text = character())
    }
    result <- quiet(backfill_day(day, fake_r2(log), FALSE, query, fake_execute(log), fake_event(log, "New one"), fake_image(log)))
    expect_equal(result, "backfilled")
    expect_equal(
        log$whats(),
        c("query", "generate_event", "query", "execute", "r2_exists", "generate_image", "r2_upload")
    )
    expect_match(log$calls[[4]]$sql, "INSERT INTO prompts")
    expect_equal(log$calls[[4]]$params, list("New one", "2026-11-03"))
})

test_that("a caption changed by a safety block updates the existing row", {
    log <- new_log()
    quiet(backfill_day(
        day, fake_r2(log), FALSE, fake_query(log, "Original"), fake_execute(log), fake_event(log),
        fake_image(log, caption = "Rewritten", changed = TRUE)
    ))
    update <- Filter(\(x) x$what == "execute", log$calls)[[1]]
    expect_match(update$sql, "UPDATE prompts SET text")
    expect_equal(update$params, list("Rewritten", "2026-11-03"))
    expect_true(match("execute", log$whats()) < match("r2_upload", log$whats()))
})

test_that("--regenerate makes a new event and image, uploads, and updates Turso last", {
    log <- new_log()
    result <- quiet(backfill_day(day, fake_r2(log, exists = TRUE), TRUE, fake_query(log, "Old"), fake_execute(log), fake_event(log, "Fresh"), fake_image(log)))
    expect_equal(result, "regenerated")
    expect_equal(log$whats(), c("generate_event", "generate_image", "r2_upload", "query", "execute"))
    expect_equal(log$calls[[2]]$prompt, "Fresh")
    expect_match(log$calls[[5]]$sql, "UPDATE prompts SET text")
    expect_equal(log$calls[[5]]$params, list("Fresh", "2026-11-03"))
})

test_that("--regenerate leaves the old day untouched when the image or the upload fails", {
    log <- new_log()
    expect_error(
        quiet(backfill_day(day, fake_r2(log, TRUE), TRUE, fake_query(log, "Old"), fake_execute(log), fake_event(log), fake_image(log, fail = TRUE))),
        "image failed"
    )
    expect_false(any(c("r2_upload", "query", "execute") %in% log$whats()))

    log <- new_log()
    r2 <- fake_r2(log, TRUE)
    r2$upload <- function(image, key) stop("Failed to upload image to R2")
    expect_error(
        quiet(backfill_day(day, r2, TRUE, fake_query(log, "Old"), fake_execute(log), fake_event(log), fake_image(log))),
        "Failed to upload"
    )
    expect_false(any(c("query", "execute") %in% log$whats()))
})

# r2_object_key and r2_client ----

test_that("the object key matches the names the app reads", {
    expect_equal(r2_object_key("2026-11-03"), "gallery-of-the-day-2026-11-03.png")
    expect_equal(r2_object_key(day), "gallery-of-the-day-2026-11-03.png")
})

test_that("r2_client calls aws.s3 with the credentials, the endpoint and an empty region", {
    skip_if_not_installed("aws.s3")
    seen <- list()
    testthat::local_mocked_bindings(
        head_object = function(...) { seen$head <<- list(...); TRUE },
        put_object  = function(...) { seen$put <<- list(...); TRUE },
        .package = "aws.s3"
    )
    r2 <- r2_client("acct", "AKID", "SECRET", "bucket")

    expect_true(r2$exists("k.png"))
    expect_equal(seen$head, list(object = "k.png", bucket = "bucket", key = "AKID", secret = "SECRET",
                                 base_url = "acct.r2.cloudflarestorage.com", region = ""))

    bytes <- NULL
    seen$put <- NULL
    testthat::local_mocked_bindings(
        put_object = function(file, ...) { bytes <<- readBin(file, "raw", 10); seen$put <<- list(file = file, ...); TRUE },
        .package = "aws.s3"
    )
    quiet(r2$upload(png, "k.png"))
    expect_identical(bytes, png)
    expect_equal(seen$put[c("object", "bucket", "key", "secret", "base_url", "region")],
                 list(object = "k.png", bucket = "bucket", key = "AKID", secret = "SECRET",
                      base_url = "acct.r2.cloudflarestorage.com", region = ""))
    expect_false(file.exists(seen$put$file))
})

test_that("an object that is missing, or any error, counts as not existing", {
    skip_if_not_installed("aws.s3")
    r2 <- r2_client("a", "k", "s", "b")
    testthat::local_mocked_bindings(head_object = function(...) FALSE, .package = "aws.s3")
    expect_false(r2$exists("x"))
    testthat::local_mocked_bindings(head_object = function(...) stop("404"), .package = "aws.s3")
    expect_false(r2$exists("x"))
})
