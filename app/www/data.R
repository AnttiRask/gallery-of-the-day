# The app's data layer. load_prompts() never throws: the server shows a message for
# each status instead of an R error page. The real error goes to the log
# (Cloud Run's), never to the visitor.
#
# status: "ok" (data has rows), "empty" (the table has no rows), "unavailable"
# (Turso could not be reached or returned an error)
load_prompts <- function() {
    data <- tryCatch(
        turso_query("SELECT date, text FROM prompts ORDER BY date"),
        error = function(e) {
            message("Loading the prompts failed: ", conditionMessage(e))
            NULL
        }
    )

    if (!is.data.frame(data) || !all(c("date", "text") %in% names(data))) {
        return(list(status = "unavailable", data = NULL))
    }
    if (nrow(data) == 0) {
        return(list(status = "empty", data = NULL))
    }
    list(status = "ok", data = data)
}
