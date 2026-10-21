# Deployment Guide

## Prerequisites

- [Google Cloud SDK (gcloud)](https://cloud.google.com/sdk/docs/install)
- [Docker](https://docs.docker.com/get-docker/) (for local testing)
- A Google Cloud account with billing enabled

## Local Development

1. Copy `.env.example` to `.env` and fill in your credentials:
   ```bash
   cp .env.example .env
   ```

2. Build and run with Docker Compose:
   ```bash
   docker compose up --build
   ```

3. Open http://localhost:8083

The `app/` directory is volume-mounted, so code changes are reflected without rebuilding.

The image is the production image: Ubuntu 24.04 with R 4.5.2, running as a non-root user. The first build restores the R packages (a few minutes); later builds reuse the cached layer until `renv.lock` changes. The app's `www/security.R` sends the security headers; check them with `curl -sI http://localhost:8083/`.

## Deploy to Google Cloud Run

### Automated Deployment

```bash
./deploy.sh
```

This will:
- Create the GCP project (if needed)
- Enable required APIs
- Build the container image
- Deploy to Cloud Run

### First-Time Setup

After the initial deploy, set up secrets:

```bash
# Enable Secret Manager API
gcloud services enable secretmanager.googleapis.com

# Create secrets
echo -n "your-turso-url" | gcloud secrets create TURSO_DATABASE_URL --data-file=-
echo -n "your-turso-token" | gcloud secrets create TURSO_AUTH_TOKEN --data-file=-
echo -n "your-r2-public-url" | gcloud secrets create R2_PUBLIC_URL --data-file=-

# The app runs as its own account that can read these three secrets and nothing
# else (not as the default compute account, which holds roles/editor)
gcloud iam service-accounts create gallery-runtime --display-name "Gallery of the Day runtime"
for s in TURSO_DATABASE_URL TURSO_AUTH_TOKEN R2_PUBLIC_URL; do
    gcloud secrets add-iam-policy-binding $s \
        --member="serviceAccount:gallery-runtime@gallery-of-the-day-app.iam.gserviceaccount.com" \
        --role="roles/secretmanager.secretAccessor"
done

# Redeploy with secrets (deploy.sh sets the service account and --max-instances 3)
gcloud run deploy gallery-of-the-day-app \
    --region europe-north1 \
    --service-account gallery-runtime@gallery-of-the-day-app.iam.gserviceaccount.com \
    --set-secrets="TURSO_DATABASE_URL=TURSO_DATABASE_URL:latest,TURSO_AUTH_TOKEN=TURSO_AUTH_TOKEN:latest,R2_PUBLIC_URL=R2_PUBLIC_URL:latest"
```

### Identities and keyless deploys

- **Runtime:** `gallery-runtime` (no project roles; `secretAccessor` on the 3 secrets only). The default compute account lost `roles/editor` and keeps `roles/cloudbuild.builds.builder`, which Cloud Build needs.
- **GitHub deploys:** the workflow `deploy_shiny_app.yml` (manual: Actions > "Deploy to Cloud Run") logs in with no stored key, through Workload Identity Federation: pool `gallery`, provider `github-oidc`, which accepts only `AnttiRask/gallery-of-the-day` on `refs/heads/main`. It acts as `gallery-deploy`, which can deploy this one service and nothing else: `run.developer` on the service, `serviceAccountUser` on the runtime and compute accounts, `artifactregistry.writer` on the one repository, `objectAdmin` and `legacyBucketReader` on the `_cloudbuild` bucket, and project-wide only `cloudbuild.builds.editor` and the custom role `galleryBucketLister` (just `storage.buckets.list`: `builds submit` lists buckets).
- **Why the build is `--async`:** `gallery-deploy` is not a project Viewer, so it can't stream the build log and `builds submit` would exit with an error even when the build succeeds. The workflow polls the build status instead.
- Tested: from `main` the whole chain passes; from another branch the login is refused (`unauthorized_client`); as the account itself, reading secrets, changing IAM, listing accounts and creating another service are all denied.

### Image cleanup

Every deploy pushes a ~240 MB image to the `cloud-run-source-deploy` repository (5.2 GB had piled up by October 2026). A cleanup policy on the repository (it runs daily) keeps the 5 most recent versions and deletes any version older than 14 days; keep rules win, so the live image (always among the newest) is safe. To change it, edit the numbers and run `gcloud artifacts repositories set-cleanup-policies cloud-run-source-deploy --location europe-north1 --project gallery-of-the-day-app --policy FILE.json` (add `--dry-run` to test first; the result only shows in the audit log after the next daily run).

### Custom Domain

```bash
gcloud beta run domain-mappings create \
    --service gallery-of-the-day-app \
    --domain galleryoftheday.youcanbeapirate.com \
    --region europe-north1
```

Then add a CNAME record in Netlify:
- Name: `galleryoftheday`
- Value: `ghs.googlehosted.com`

SSL certificate provisioning takes 15-30 minutes.

## Updating

To deploy updates:

```bash
./deploy.sh
```

## Monitoring

```bash
# View logs
gcloud run logs read --service gallery-of-the-day-app --region europe-north1

# Check service status
gcloud run services describe gallery-of-the-day-app --region europe-north1
```

### Uptime check and alerts

`GET https://galleryoftheday.youcanbeapirate.com/health` answers 200 `ok`, or 503 with a reason (`unavailable`, `empty`, `stale`: the newest image is more than a day old, `degraded`: the cached prompts are served because Turso fails). `/` is not enough: it returns 200 even when Turso is down or the daily job has failed. Open `/health` in a browser to see which problem it is.

Set up in Cloud Monitoring (project `gallery-of-the-day-app`, all created with gcloud on 2026-10-21):
- **Uptime check** "Gallery of the Day /health": HTTPS GET `/health` every 5 minutes from all 6 regions, 10 s timeout, valid SSL required, 2xx and a body containing `ok` (check id `gallery-of-the-day-health-t_CCZEBpjQM`). About 255,000 results a month, under the free 1 million executions ($0.30 per 1,000 above it).
- **Email channel** "Gallery of the Day alerts" to the owner's address (`gcloud beta monitoring channels list`).
- **Alert policy** "Gallery of the Day: /health failing": fires when the check fails from more than one region for 10 minutes, closes itself on recovery. The definition is in `monitoring/health-alert-policy.json`; recreate it with `gcloud monitoring policies create --project gallery-of-the-day-app --policy-from-file=monitoring/health-alert-policy.json` (the channel and check ids in the file are this project's).
- Tested end to end on 2026-10-21 with a temporary always-failing check: the alert opened after about 7 minutes, the email arrived, and it closed by itself 7 minutes after the check was fixed. The temporary check and policy were deleted. (The test policy used a 60 s duration instead of 600 s.)

## Cost

Google Cloud Run free tier includes:
- 2 million requests/month
- 360,000 GB-seconds of memory
- 180,000 vCPU-seconds

This app should stay well within the free tier.

A budget named "Gallery of the Day" (EUR 10 a month, this project only) emails the billing account's admins at 50%, 90% and 100% of actual spend. It only alerts; `--max-instances 3` is what limits the cost. Manage it with `gcloud billing budgets list --billing-account 01022A-90DC69-4116A8` (the Budget API is enabled on the project).
