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

# Grant Cloud Run access to secrets
PROJECT_NUMBER=$(gcloud projects describe gallery-of-the-day-app --format="value(projectNumber)")
gcloud secrets add-iam-policy-binding TURSO_DATABASE_URL \
    --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor"
gcloud secrets add-iam-policy-binding TURSO_AUTH_TOKEN \
    --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor"
gcloud secrets add-iam-policy-binding R2_PUBLIC_URL \
    --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor"

# Redeploy with secrets
gcloud run deploy gallery-of-the-day-app \
    --region europe-north1 \
    --set-secrets="TURSO_DATABASE_URL=TURSO_DATABASE_URL:latest,TURSO_AUTH_TOKEN=TURSO_AUTH_TOKEN:latest,R2_PUBLIC_URL=R2_PUBLIC_URL:latest"
```

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

## Cost

Google Cloud Run free tier includes:
- 2 million requests/month
- 360,000 GB-seconds of memory
- 180,000 vCPU-seconds

This app should stay well within the free tier.
