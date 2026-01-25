# One-time script to migrate prompts.csv to Turso database
# Run locally with credentials in secret.R
#
# Prerequisites:
# 1. Create Turso database: turso db create gallery-of-the-day
# 2. Create table:
#    turso db shell gallery-of-the-day
#    CREATE TABLE prompts (id INTEGER PRIMARY KEY AUTOINCREMENT, text TEXT NOT NULL, date TEXT NOT NULL UNIQUE);
#    CREATE INDEX idx_prompts_date ON prompts(date);
# 3. Add credentials to secret.R:
#    TURSO_DATABASE_URL <- "libsql://..."
#    TURSO_AUTH_TOKEN <- "..."
#
# Usage: source("R/migrate_prompts_to_turso.R")

# Load credentials from secret.R
source("secret.R")

# Load Turso helper functions
source("R/turso.R")

# Load packages
library(readr)

# Read existing prompts
csv_path <- "app/data/prompts.csv"

if (!file.exists(csv_path)) {
    cat("No prompts.csv file found. Nothing to migrate.\n")
} else {
    prompts <- read_csv(csv_path, col_types = cols(text = col_character(), date = col_character()))

    if (nrow(prompts) == 0) {
        cat("prompts.csv is empty. Nothing to migrate.\n")
    } else {
        cat("Found", nrow(prompts), "prompts to migrate.\n\n")

        success_count <- 0
        skip_count <- 0
        error_count <- 0

        for (i in 1:nrow(prompts)) {
            prompt_text <- prompts$text[i]
            prompt_date <- prompts$date[i]

            cat("Migrating:", prompt_date, "... ")

            # Check if already exists
            existing <- tryCatch({
                turso_query(
                    "SELECT COUNT(*) as count FROM prompts WHERE date = ?",
                    list(prompt_date)
                )
            }, error = function(e) {
                cat("ERROR checking:", conditionMessage(e), "\n")
                return(NULL)
            })

            if (is.null(existing)) {
                error_count <- error_count + 1
                next
            }

            if (as.integer(existing$count[1]) > 0) {
                cat("SKIPPED (already exists)\n")
                skip_count <- skip_count + 1
                next
            }

            # Insert into Turso
            result <- tryCatch({
                turso_execute(
                    "INSERT INTO prompts (text, date) VALUES (?, ?)",
                    list(prompt_text, prompt_date)
                )
                TRUE
            }, error = function(e) {
                cat("ERROR:", conditionMessage(e), "\n")
                FALSE
            })

            if (result) {
                cat("OK\n")
                success_count <- success_count + 1
            } else {
                error_count <- error_count + 1
            }
        }

        cat("\n")
        cat("Migration complete!\n")
        cat("  Migrated:", success_count, "\n")
        cat("  Skipped:", skip_count, "\n")
        cat("  Errors:", error_count, "\n")
    }
}
