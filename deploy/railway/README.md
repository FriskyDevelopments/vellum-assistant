# Vellum → Google Artifact Registry → Railway

This package reuses the existing `deploy/zeabur/Dockerfile` and `deploy/zeabur/entrypoint.sh` on branch `feat/zeabur-one-container`. Google Cloud Build builds from the Git checkout and publishes an immutable image to Google Artifact Registry (GAR). Railway pulls and runs that image.

## Apply to the existing Git repository

From the Vellum checkout:

```bash
cd /Users/friskypup/Developer/vellum-assistant
git checkout feat/zeabur-one-container
mkdir -p deploy/railway
cp /path/to/package/deploy/railway/* deploy/railway/
git add deploy/railway
git commit -m "feat: deploy Vellum to Railway through GAR"
git push fork feat/zeabur-one-container
```

## Build and publish with gcloud

```bash
gcloud auth login
gcloud config set project friskyvellum
./deploy/railway/deploy.sh
```

The script enables Artifact Registry and Cloud Build, creates a Docker repository named `vellum` in `us-central1` if it does not exist, builds the existing one-container Dockerfile, tags it with the current Git commit, pushes it, and prints `IMAGE_URI`.

## Give Railway pull-only access

```bash
./deploy/railway/create-reader.sh
```

In Railway, create a **Docker Image** service using the printed `IMAGE_URI`. Under **Source → Registry Credentials**, use:

```text
Username: _json_key
Password: entire contents of railway-gar-reader.json
```

Delete the downloaded JSON key locally after Railway has stored it. Never commit it.

## Railway runtime

Attach one Railway volume at:

```text
/data
```

Set these variables:

```text
VELLUM_DATA_DIR=/data
VELLUM_ASSISTANT_NAME=frisky-vellum
VELLUM_ENVIRONMENT=production
VELLUM_DISABLE_PLATFORM=true
GATEWAY_TRUST_PROXY=true
```

Add at least one model-provider secret in Railway:

```text
ANTHROPIC_API_KEY=...
# or OPENAI_API_KEY=...
# or GEMINI_API_KEY=...
```

Set the health-check path to `/readyz` and allow at least 180 seconds for first startup. Railway supplies `PORT`; the existing entrypoint forwards it to Vellum's internal gateway on port 7830.

Generate a Railway domain only after the deployment is healthy. Protect the public endpoint with Cloudflare Access before connecting real accounts or tools.

## Update and rollback

For each revision:

```bash
git add -A
git commit -m "your change"
git push fork feat/zeabur-one-container
./deploy/railway/deploy.sh
```

Update Railway to the newly printed commit-tagged image URI and redeploy. To roll back, choose a previous Git-SHA image tag.
