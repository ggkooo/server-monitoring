#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <dockerhub-user> [tag]"
  exit 1
fi

DOCKERHUB_USER="$1"
TAG="${2:-latest}"
RELEASES_DIR="releases"
RELEASES_FILE="${RELEASES_DIR}/${TAG}.env"

random_alnum() {
  local length="$1"
  local result=""
  while [[ ${#result} -lt "$length" ]]; do
    result+="$(tr -dc 'a-z0-9' </dev/urandom | head -c "$length" || true)"
  done
  printf '%s' "${result:0:length}"
}

random_id() {
  shuf -i 100000-999999 -n 1
}

# Use existing release manifest for this tag or generate new credentials.
# The REVERB_APP_KEY is baked into the frontend image at build time,
# so reusing the same key for rebuilds of the same tag keeps everything consistent.
if [[ -f "$RELEASES_FILE" ]]; then
  echo "Using existing release manifest from ${RELEASES_FILE}..."
  while IFS='=' read -r key val; do
    [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
    key="${key%%[[:space:]]*}"
    val="${val%%[[:space:]]*}"
    case "$key" in
      REVERB_APP_KEY) REVERB_APP_KEY="$val" ;;
      REVERB_APP_ID)  REVERB_APP_ID="$val"  ;;
    esac
  done <"$RELEASES_FILE"
else
  echo "Generating new REVERB credentials for ${TAG}..."
  REVERB_APP_ID="$(random_id)"
  REVERB_APP_KEY="$(random_alnum 20)"
  mkdir -p "$RELEASES_DIR"
  cat >"$RELEASES_FILE" <<EOF
# REVERB credentials baked into pre-built hub images for ${TAG}
# REVERB_APP_KEY is embedded in the frontend image at build time.
# It MUST match the backend REVERB_APP_KEY — do not change this file.
# REVERB_APP_SECRET is not stored here and will be auto-generated per deployment.
REVERB_APP_KEY=${REVERB_APP_KEY}
REVERB_APP_ID=${REVERB_APP_ID}
EOF
  echo "Saved release manifest to ${RELEASES_FILE}"
fi

VITE_WS_URL="/app/${REVERB_APP_KEY}?protocol=7&client=js&version=8.4.0&flash=false"
echo "REVERB_APP_KEY for this build: ${REVERB_APP_KEY}"

echo "Building frontend image..."
docker build \
  -t "${DOCKERHUB_USER}/server-monitoring-frontend:${TAG}" \
  -f f-server-monitoring/Dockerfile \
  --build-arg VITE_METRICS_WS_URL="${VITE_WS_URL}" \
  --build-arg VITE_METRICS_CHANNEL="metrics" \
  f-server-monitoring

echo "Building Prometheus image..."
docker build \
  -t "${DOCKERHUB_USER}/server-monitoring-prometheus:${TAG}" \
  -f monitoring/Dockerfile.prometheus \
  .

echo "Building Process Exporter image..."
docker build \
  -t "${DOCKERHUB_USER}/server-monitoring-process-exporter:${TAG}" \
  -f monitoring/Dockerfile.process-exporter \
  .

echo "Building Edge Nginx image..."
docker build \
  -t "${DOCKERHUB_USER}/server-monitoring-edge-nginx:${TAG}" \
  -f nginx/Dockerfile.edge \
  nginx

echo "Building backend image..."
docker build \
  -t "${DOCKERHUB_USER}/server-monitoring-backend:${TAG}" \
  -f b-server-monitoring/Dockerfile \
  b-server-monitoring

echo "Pushing images to Docker Hub..."
docker push "${DOCKERHUB_USER}/server-monitoring-frontend:${TAG}"
docker push "${DOCKERHUB_USER}/server-monitoring-prometheus:${TAG}"
docker push "${DOCKERHUB_USER}/server-monitoring-process-exporter:${TAG}"
docker push "${DOCKERHUB_USER}/server-monitoring-edge-nginx:${TAG}"
docker push "${DOCKERHUB_USER}/server-monitoring-backend:${TAG}"

echo "Done. Images published:"
echo "- ${DOCKERHUB_USER}/server-monitoring-frontend:${TAG}"
echo "- ${DOCKERHUB_USER}/server-monitoring-prometheus:${TAG}"
echo "- ${DOCKERHUB_USER}/server-monitoring-process-exporter:${TAG}"
echo "- ${DOCKERHUB_USER}/server-monitoring-edge-nginx:${TAG}"
echo "- ${DOCKERHUB_USER}/server-monitoring-backend:${TAG}"
