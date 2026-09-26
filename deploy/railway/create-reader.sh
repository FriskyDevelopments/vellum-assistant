#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-friskyvellum}"
REGION="${GAR_REGION:-us-central1}"
REPOSITORY="${GAR_REPOSITORY:-vellum}"
SA_NAME="${GAR_READER_SA:-railway-gar-reader}"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
KEY_FILE="${1:-railway-gar-reader.json}"

gcloud iam service-accounts describe "$SA_EMAIL" --project "$PROJECT_ID" >/dev/null 2>&1 || \
  gcloud iam service-accounts create "$SA_NAME" \
    --display-name="Railway Artifact Registry reader" \
    --project="$PROJECT_ID"

gcloud artifacts repositories add-iam-policy-binding "$REPOSITORY" \
  --location="$REGION" \
  --project="$PROJECT_ID" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/artifactregistry.reader"

gcloud iam service-accounts keys create "$KEY_FILE" \
  --iam-account="$SA_EMAIL" \
  --project="$PROJECT_ID"

chmod 600 "$KEY_FILE"
printf '\nRailway registry username: _json_key\n'
printf 'Railway registry password: entire contents of %s\n' "$KEY_FILE"
printf 'Delete this local key after storing it in Railway. Never commit it.\n'
