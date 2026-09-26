#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-friskyvellum}"
REGION="${GAR_REGION:-us-central1}"
REPOSITORY="${GAR_REPOSITORY:-vellum}"
IMAGE="${GAR_IMAGE:-vellum-assistant}"
TAG="${1:-$(git rev-parse --short=12 HEAD)}"
IMAGE_URI="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}/${IMAGE}:${TAG}"

gcloud config set project "$PROJECT_ID"
gcloud services enable artifactregistry.googleapis.com cloudbuild.googleapis.com --project "$PROJECT_ID"

if ! gcloud artifacts repositories describe "$REPOSITORY" \
  --location "$REGION" --project "$PROJECT_ID" >/dev/null 2>&1; then
  gcloud artifacts repositories create "$REPOSITORY" \
    --repository-format=docker \
    --location="$REGION" \
    --description="Vellum images for Railway" \
    --project="$PROJECT_ID"
fi

gcloud builds submit . \
  --project "$PROJECT_ID" \
  --config deploy/railway/cloudbuild.yaml \
  --substitutions "_REGION=${REGION},_REPOSITORY=${REPOSITORY},_IMAGE=${IMAGE},_TAG=${TAG}"

printf '\nIMAGE_URI=%s\n' "$IMAGE_URI"
printf 'Use this exact image URI as the Railway Docker Image source.\n'
