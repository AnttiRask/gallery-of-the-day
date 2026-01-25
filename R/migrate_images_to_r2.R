# One-time script to migrate existing images to Cloudflare R2
# Run locally with credentials in secret.R
#
# Usage: source("R/migrate_images_to_r2.R")

# Load credentials from secret.R
source("secret.R")

# Load packages
library(aws.s3)
library(stringr)

# Construct R2 endpoint (without https:// prefix for aws.s3 package)
r2_endpoint <- str_glue("{R2_ACCOUNT_ID}.r2.cloudflarestorage.com")

# Find all existing images
images <- list.files("app/img/", pattern = "\\.png$", full.names = TRUE)

if (length(images) == 0) {
    cat("No images found to migrate.\n")
} else {
    cat("Found", length(images), "images to migrate.\n\n")

    for (img_path in images) {
        object_key <- basename(img_path)

        cat("Uploading:", object_key, "... ")

        result <- tryCatch({
            put_object(
                file     = img_path,
                object   = object_key,
                bucket   = R2_BUCKET_NAME,
                key      = R2_ACCESS_KEY_ID,
                secret   = R2_SECRET_ACCESS_KEY,
                base_url = r2_endpoint,
                region   = ""
            )
        }, error = function(e) {
            cat("FAILED:", conditionMessage(e), "\n")
            return(FALSE)
        })

        if (isTRUE(result)) {
            cat("OK\n")
        }
    }

    cat("\nMigration complete!\n")
    cat("\nTo verify, check your R2 bucket in the Cloudflare dashboard.\n")
    cat("Once confirmed, you can delete local images with:\n")
    cat("  unlink('app/img/gallery-of-the-day-*.png')\n")
}
