## Settings shared by run.R (security headers) and config.R (the app's image URLs)

# Public URL of the Cloudflare R2 bucket the images come from. The R2_PUBLIC_URL
# environment variable overrides it; local development uses this default.
r2_public_url_default <- "https://pub-fa8ba5f601374e88994818db80a1c9d2.r2.dev"
