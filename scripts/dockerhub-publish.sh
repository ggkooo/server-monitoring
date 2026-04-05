#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <dockerhub-user> [tag]"
  exit 1
fi

DOCKERHUB_USER="$1"
TAG="${2:-latest}"

echo "Building frontend image..."
docker build \
  -t "${DOCKERHUB_USER}/server-monitoring-frontend:${TAG}" \
  -f f-server-monitoring/Dockerfile \
  --build-arg VITE_METRICS_WS_URL="/app/lbvk6nsfyjta5at2mar1?protocol=7&client=js&version=8.4.0&flash=false" \
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
