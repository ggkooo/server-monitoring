#!/usr/bin/env bash
set -euo pipefail

REPO="ggkooo/server-monitoring"
REF="master"
COMPOSE_FILE="docker-compose.hub.yml"
ENV_FILE=".env.hub"
DOCKERHUB_USER="giordanoberwig"
IMAGE_TAG="v1.0.1"
APP_PORT="8991"
DOCKER_NETWORK_NAME="server-monitoring-network"
APP_ENV="production"
APP_DEBUG="false"
APP_URL="http://localhost"
PROMETHEUS_USERNAME=""
PROMETHEUS_PASSWORD=""
CREDENTIALS_FILE=""
RUN_PULL="true"
RUN_UP="false"

usage() {
  cat <<'EOF'
Usage: hub-bootstrap.sh [options]

Downloads docker-compose.hub.yml, creates/updates .env.hub with generated
credentials, then runs docker compose pull (and optionally up -d).

Options:
  --repo <owner/repo>      GitHub repo (default: ggkooo/server-monitoring)
  --ref <git-ref>          Git ref/branch/tag (default: master)
  --compose-file <path>    Compose output path (default: docker-compose.hub.yml)
  --env-file <path>        Env output path (default: .env.hub)
  --dockerhub-user <user>  Docker Hub username (default: giordanoberwig)
  --image-tag <tag>        Image tag (default: v1.0.1)
  --app-port <port>        Host port for edge nginx (default: 8991)
  --network-name <name>    Docker network name (default: server-monitoring-network)
  --prom-user <username>   Prometheus username (default: auto-generated)
  --prom-pass <password>   Prometheus password (default: auto-generated)
  --credentials-file <path>
                           Save generated credentials to a separate file
  --up                     Run 'docker compose ... up -d' after pull
  --skip-pull              Skip 'docker compose ... pull'
  -h, --help               Show this help message

Examples:
  bash hub-bootstrap.sh
  bash hub-bootstrap.sh --dockerhub-user myuser --image-tag v1.0.1 --up
  bash hub-bootstrap.sh --ref v1.0.1 --prom-user ggko --prom-pass 'StrongPass!123'
  bash hub-bootstrap.sh --credentials-file credentials.txt
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="${2:?Missing value for --repo}"
      shift 2
      ;;
    --ref)
      REF="${2:?Missing value for --ref}"
      shift 2
      ;;
    --compose-file)
      COMPOSE_FILE="${2:?Missing value for --compose-file}"
      shift 2
      ;;
    --env-file)
      ENV_FILE="${2:?Missing value for --env-file}"
      shift 2
      ;;
    --dockerhub-user)
      DOCKERHUB_USER="${2:?Missing value for --dockerhub-user}"
      shift 2
      ;;
    --image-tag)
      IMAGE_TAG="${2:?Missing value for --image-tag}"
      shift 2
      ;;
    --app-port)
      APP_PORT="${2:?Missing value for --app-port}"
      shift 2
      ;;
    --network-name)
      DOCKER_NETWORK_NAME="${2:?Missing value for --network-name}"
      shift 2
      ;;
    --prom-user)
      PROMETHEUS_USERNAME="${2:?Missing value for --prom-user}"
      shift 2
      ;;
    --prom-pass)
      PROMETHEUS_PASSWORD="${2:?Missing value for --prom-pass}"
      shift 2
      ;;
    --credentials-file)
      CREDENTIALS_FILE="${2:?Missing value for --credentials-file}"
      shift 2
      ;;
    --up)
      RUN_UP="true"
      shift
      ;;
    --skip-pull)
      RUN_PULL="false"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: missing required command '$1'." >&2
    exit 1
  fi
}

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

escape_sed_replacement() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//&/\\&}"
  printf '%s' "$value"
}

upsert_env_var() {
  local file="$1"
  local key="$2"
  local raw_value="$3"
  local value

  value="$(escape_sed_replacement "$raw_value")"

  if grep -qE "^${key}=" "$file"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$file"
  else
    printf '%s=%s\n' "$key" "$raw_value" >>"$file"
  fi
}

need_cmd curl
need_cmd docker

if ! docker compose version >/dev/null 2>&1; then
  echo "Error: docker compose plugin is required." >&2
  exit 1
fi

download_compose() {
  local ref="$1"
  local url="https://raw.githubusercontent.com/${REPO}/${ref}/docker-compose.hub.yml"

  echo "Downloading compose file from ${url}..."
  curl -fsSL "$url" -o "$COMPOSE_FILE"
}

if ! download_compose "$REF"; then
  if [[ "$REF" == "main" ]]; then
    echo "Primary ref failed. Trying fallback ref 'master'..."
    download_compose "master"
  elif [[ "$REF" == "master" ]]; then
    echo "Primary ref failed. Trying fallback ref 'main'..."
    download_compose "main"
  else
    echo "Error: could not download docker-compose.hub.yml from ref '${REF}'." >&2
    exit 1
  fi
fi

if [[ ! -f "$ENV_FILE" ]]; then
  : >"$ENV_FILE"
fi

if [[ -z "$PROMETHEUS_USERNAME" ]]; then
  PROMETHEUS_USERNAME="prom_$(random_alnum 10)"
fi

if [[ -z "$PROMETHEUS_PASSWORD" ]]; then
  PROMETHEUS_PASSWORD="$(random_alnum 24)"
fi

REVERB_APP_ID="$(random_id)"
REVERB_APP_KEY="$(random_alnum 20)"
REVERB_APP_SECRET="$(random_alnum 20)"

upsert_env_var "$ENV_FILE" "DOCKERHUB_USER" "$DOCKERHUB_USER"
upsert_env_var "$ENV_FILE" "IMAGE_TAG" "$IMAGE_TAG"
upsert_env_var "$ENV_FILE" "APP_PORT" "$APP_PORT"
upsert_env_var "$ENV_FILE" "DOCKER_NETWORK_NAME" "$DOCKER_NETWORK_NAME"
upsert_env_var "$ENV_FILE" "APP_ENV" "$APP_ENV"
upsert_env_var "$ENV_FILE" "APP_DEBUG" "$APP_DEBUG"
upsert_env_var "$ENV_FILE" "APP_URL" "$APP_URL"
upsert_env_var "$ENV_FILE" "REVERB_APP_ID" "$REVERB_APP_ID"
upsert_env_var "$ENV_FILE" "REVERB_APP_KEY" "$REVERB_APP_KEY"
upsert_env_var "$ENV_FILE" "REVERB_APP_SECRET" "$REVERB_APP_SECRET"
upsert_env_var "$ENV_FILE" "PROMETHEUS_USERNAME" "$PROMETHEUS_USERNAME"
upsert_env_var "$ENV_FILE" "PROMETHEUS_PASSWORD" "$PROMETHEUS_PASSWORD"

echo "Generated credentials in ${ENV_FILE}:"
echo "REVERB_APP_ID=${REVERB_APP_ID}"
echo "REVERB_APP_KEY=${REVERB_APP_KEY}"
echo "REVERB_APP_SECRET=${REVERB_APP_SECRET}"
echo "PROMETHEUS_USERNAME=${PROMETHEUS_USERNAME}"
echo "PROMETHEUS_PASSWORD=${PROMETHEUS_PASSWORD}"

if [[ -n "$CREDENTIALS_FILE" ]]; then
  umask 077
  cat >"$CREDENTIALS_FILE" <<EOF
# Generated by hub-bootstrap.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)
REVERB_APP_ID=${REVERB_APP_ID}
REVERB_APP_KEY=${REVERB_APP_KEY}
REVERB_APP_SECRET=${REVERB_APP_SECRET}
PROMETHEUS_USERNAME=${PROMETHEUS_USERNAME}
PROMETHEUS_PASSWORD=${PROMETHEUS_PASSWORD}
EOF
  echo "Saved credentials backup to ${CREDENTIALS_FILE}"
  echo "Warning: keep this file private."
fi

if [[ "$RUN_PULL" == "true" ]]; then
  echo "Pulling images..."
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" pull
fi

if [[ "$RUN_UP" == "true" ]]; then
  echo "Starting services..."
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d
fi

echo "Done."
echo "Compose file: ${COMPOSE_FILE}"
echo "Env file: ${ENV_FILE}"
echo "Dashboard URL: http://localhost:${APP_PORT}"
