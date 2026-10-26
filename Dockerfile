# R 4.5.2 matches renv.lock; r-ver is much smaller than rocker/shiny and we only
# need R, because app/run.R starts the app with shiny::runApp()
FROM rocker/r-ver:4.6.1

# System libraries needed by the app's R packages on this Ubuntu release. The list
# comes from Posit Package Manager's sysreqs API (for Ubuntu 24.04):
#   https://p3m.dev/__api__/repos/cran/sysreqs?distribution=ubuntu&release=24.04&pkgname=...
# cmake and make are only used if a locked package has to be compiled.
RUN for i in 1 2 3; do \
        apt-get update && apt-get install -y --no-install-recommends \
            cmake \
            make \
            libcurl4-openssl-dev \
            libicu-dev \
            libssl-dev \
            libuv1-dev \
            zlib1g-dev \
        && break || { echo "apt attempt $i failed, retrying in $((i*15))s"; sleep $((i*15)); }; \
    done \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# renv infrastructure first, so the (slow) package layer is cached until the
# lockfile changes
COPY renv.lock renv.lock
COPY .Rprofile .Rprofile
COPY renv/activate.R renv/activate.R
COPY renv/settings.json renv/settings.json

# No renv cache: by default renv installs into a cache under the build user's
# home (/root) and only symlinks packages into the project library, which the
# non-root runtime user can't read. Real copies in /app/renv/library work for
# everyone (and keep the image smaller).
ENV RENV_CONFIG_CACHE_ENABLED=FALSE
# No renv sandbox at runtime (it would create directories on every start)
ENV RENV_CONFIG_SANDBOX_ENABLED=FALSE

# Restore only what the app uses (and its dependencies) from the lockfile, from
# Posit Package Manager's prebuilt Linux binaries where it has them. The lockfile
# also holds the packages of the daily scripts (aws.s3 and others), which the app
# doesn't need. renv itself is restored too, because .Rprofile activates it.
RUN CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")" \
    && R -q -e "options(renv.config.repos.override = c(CRAN = 'https://p3m.dev/cran/__linux__/${CODENAME}/latest')); renv::restore(packages = c('shiny', 'bslib', 'dplyr', 'stringr', 'httr2', 'jsonlite', 'renv'), prompt = FALSE)"

# The image restores only the app's packages, so renv's startup check would
# report the daily scripts' packages as "not installed" on every cold start
ENV RENV_CONFIG_SYNCHRONIZED_CHECK=FALSE

# Shared with the daily scripts (R/), so the app and the scripts use one Turso client
COPY R/turso.R R/turso.R
COPY app app

# Don't run as root
RUN useradd --system --create-home --shell /usr/sbin/nologin gallery \
    && chown -R gallery:gallery /app
USER gallery

# Cloud Run sets PORT; the Turso settings are injected at runtime (Secret
# Manager), never baked into the image
ENV PORT=8080
EXPOSE 8080

CMD ["Rscript", "app/run.R"]
