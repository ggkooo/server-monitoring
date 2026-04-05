#!/usr/bin/env bash
set -euo pipefail

REPO="ggkooo/server-monitoring"
REF="master"
COMPOSE_FILE="docker-compose.hub.yml"
ENV_FILE=".env.hub"
PERSIST_ENV="false"
SHOW_SECRETS="false"
DOCKERHUB_USER="giordanoberwig"
IMAGE_TAG="v1.0.1"
APP_PORT="8991"
DOCKER_NETWORK_NAME="server-monitoring-network"
APP_ENV="production"
APP_DEBUG="false"
APP_URL="http://localhost"
PROMETHEUS_USERNAME=""
PROMETHEUS_PASSWORD=""
PROMETHEUS_PASSWORD_HASH=""
PROMETHEUS_PASSWORD_HASH_B64=""
REVERB_APP_ID=""
REVERB_APP_KEY=""
REVERB_APP_SECRET=""
CREDENTIALS_FILE=""
RUN_PULL="true"
RUN_UP="false"

usage() {
  cat <<'EOF'
Usage: hub-bootstrap.sh [options]

Downloads docker-compose.hub.yml, generates random credentials, and runs
docker compose pull (and optionally up -d) using an ephemeral env file.

By default, credentials are NOT persisted to disk.

Options:
  --repo <owner/repo>      GitHub repo (default: ggkooo/server-monitoring)
  --ref <git-ref>          Git ref/branch/tag (default: master)
  --compose-file <path>    Compose output path (default: docker-compose.hub.yml)
  --env-file <path>        Env output path (default: .env.hub)
  --persist-env            Persist generated env file to --env-file
  --show-secrets           Print generated secrets to stdout (not recommended)
  --dockerhub-user <user>  Docker Hub username (default: giordanoberwig)
  --image-tag <tag>        Image tag (default: v1.0.1)
  --app-port <port>        Host port for edge nginx (default: 8991)
  --network-name <name>    Docker network name (default: server-monitoring-network)
  --prom-user <username>   Prometheus username (default: auto-generated)
  --prom-pass <password>   Prometheus password (default: auto-generated)
  --prom-pass-hash <hash>  Prometheus bcrypt hash (default: auto-generated from password)
  --prom-pass-hash-b64 <b64>
                           Prometheus bcrypt hash in base64 (default: derived)
  --reverb-app-id <id>     Reverb app ID (default: auto-generated)
  --reverb-app-key <key>   Reverb app key (default: auto-generated)
  --reverb-app-secret <s>  Reverb app secret (default: auto-generated)
  --credentials-file <path>
                           Save generated credentials to a separate file
  --up                     Run 'docker compose ... up -d' after pull
  --skip-pull              Skip 'docker compose ... pull'
  -h, --help               Show this help message

Examples:
  bash hub-bootstrap.sh
  bash hub-bootstrap.sh --dockerhub-user myuser --image-tag v1.0.1 --up
  bash hub-bootstrap.sh --ref v1.0.1 --prom-user ggko --prom-pass 'StrongPass!123'
  bash hub-bootstrap.sh --up --persist-env
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
    --persist-env)
      PERSIST_ENV="true"
      shift
      ;;
    --show-secrets)
      SHOW_SECRETS="true"
      shift
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
    --prom-pass-hash)
      PROMETHEUS_PASSWORD_HASH="${2:?Missing value for --prom-pass-hash}"
      shift 2
      ;;
    --prom-pass-hash-b64)
      PROMETHEUS_PASSWORD_HASH_B64="${2:?Missing value for --prom-pass-hash-b64}"
      shift 2
      ;;
    --reverb-app-id)
      REVERB_APP_ID="${2:?Missing value for --reverb-app-id}"
      shift 2
      ;;
    --reverb-app-key)
      REVERB_APP_KEY="${2:?Missing value for --reverb-app-key}"
      shift 2
      ;;
    --reverb-app-secret)
      REVERB_APP_SECRET="${2:?Missing value for --reverb-app-secret}"
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

generate_bcrypt_hash() {
  local password="$1"

  # Use an ephemeral helper container to avoid host package dependencies.
  docker run --rm --entrypoint htpasswd httpd:2.4-alpine -nbBC 12 "" "$password" \
    | tr -d ':\n'
}

to_base64() {
  printf '%s' "$1" | base64 | tr -d '\n'
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

RUNTIME_ENV_FILE=""
cleanup_runtime_env() {
  if [[ -n "$RUNTIME_ENV_FILE" && -f "$RUNTIME_ENV_FILE" && "$PERSIST_ENV" != "true" ]]; then
    rm -f "$RUNTIME_ENV_FILE"
  fi
}
trap cleanup_runtime_env EXIT

if [[ "$PERSIST_ENV" == "true" ]]; then
  RUNTIME_ENV_FILE="$ENV_FILE"
  if [[ ! -f "$RUNTIME_ENV_FILE" ]]; then
    : >"$RUNTIME_ENV_FILE"
  fi
else
  tmp_dir="${TMPDIR:-/tmp}"
  umask 077
  RUNTIME_ENV_FILE="$(mktemp "${tmp_dir}/.server-monitoring-env.XXXXXX")"
fi

if [[ -z "$PROMETHEUS_USERNAME" ]]; then
  PROMETHEUS_USERNAME="prom_$(random_alnum 10)"
fi

if [[ -z "$PROMETHEUS_PASSWORD" ]]; then
  PROMETHEUS_PASSWORD="$(random_alnum 24)"
fi

if [[ -z "$PROMETHEUS_PASSWORD_HASH" ]]; then
  echo "Generating Prometheus bcrypt hash..."
  PROMETHEUS_PASSWORD_HASH="$(generate_bcrypt_hash "$PROMETHEUS_PASSWORD")"
fi

if [[ -z "$PROMETHEUS_PASSWORD_HASH_B64" ]]; then
  PROMETHEUS_PASSWORD_HASH_B64="$(to_base64 "$PROMETHEUS_PASSWORD_HASH")"
fi

[[ -z "$REVERB_APP_ID" ]]     && REVERB_APP_ID="$(random_id)"
[[ -z "$REVERB_APP_KEY" ]]    && REVERB_APP_KEY="$(random_alnum 20)"
[[ -z "$REVERB_APP_SECRET" ]] && REVERB_APP_SECRET="$(random_alnum 20)"

upsert_env_var "$RUNTIME_ENV_FILE" "DOCKERHUB_USER" "$DOCKERHUB_USER"
upsert_env_var "$RUNTIME_ENV_FILE" "IMAGE_TAG" "$IMAGE_TAG"
upsert_env_var "$RUNTIME_ENV_FILE" "APP_PORT" "$APP_PORT"
upsert_env_var "$RUNTIME_ENV_FILE" "DOCKER_NETWORK_NAME" "$DOCKER_NETWORK_NAME"
upsert_env_var "$RUNTIME_ENV_FILE" "APP_ENV" "$APP_ENV"
upsert_env_var "$RUNTIME_ENV_FILE" "APP_DEBUG" "$APP_DEBUG"
upsert_env_var "$RUNTIME_ENV_FILE" "APP_URL" "$APP_URL"
upsert_env_var "$RUNTIME_ENV_FILE" "REVERB_APP_ID" "$REVERB_APP_ID"
upsert_env_var "$RUNTIME_ENV_FILE" "REVERB_APP_KEY" "$REVERB_APP_KEY"
upsert_env_var "$RUNTIME_ENV_FILE" "REVERB_APP_SECRET" "$REVERB_APP_SECRET"
upsert_env_var "$RUNTIME_ENV_FILE" "PROMETHEUS_USERNAME" "$PROMETHEUS_USERNAME"
upsert_env_var "$RUNTIME_ENV_FILE" "PROMETHEUS_PASSWORD" "$PROMETHEUS_PASSWORD"
upsert_env_var "$RUNTIME_ENV_FILE" "PROMETHEUS_PASSWORD_HASH" "$PROMETHEUS_PASSWORD_HASH"
upsert_env_var "$RUNTIME_ENV_FILE" "PROMETHEUS_PASSWORD_HASH_B64" "$PROMETHEUS_PASSWORD_HASH_B64"

echo "Generated random credentials for this bootstrap run."
if [[ "$SHOW_SECRETS" == "true" ]]; then
  echo "REVERB_APP_ID=${REVERB_APP_ID}"
  echo "REVERB_APP_KEY=${REVERB_APP_KEY}"
  echo "REVERB_APP_SECRET=${REVERB_APP_SECRET}"
  echo "PROMETHEUS_USERNAME=${PROMETHEUS_USERNAME}"
  echo "PROMETHEUS_PASSWORD=${PROMETHEUS_PASSWORD}"
else
  echo "REVERB_APP_ID=${REVERB_APP_ID}"
  echo "REVERB_APP_KEY=${REVERB_APP_KEY:0:4}...${REVERB_APP_KEY: -4}"
  echo "REVERB_APP_SECRET=<hidden>"
  echo "PROMETHEUS_USERNAME=${PROMETHEUS_USERNAME}"
  echo "PROMETHEUS_PASSWORD=<hidden>"
fi

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
  docker compose --env-file "$RUNTIME_ENV_FILE" -f "$COMPOSE_FILE" pull
fi

if [[ "$RUN_UP" == "true" ]]; then
  echo "Starting services..."
  docker compose --env-file "$RUNTIME_ENV_FILE" -f "$COMPOSE_FILE" up -d
fi

echo "Done."
echo "Compose file: ${COMPOSE_FILE}"
if [[ "$PERSIST_ENV" == "true" ]]; then
  echo "Env file persisted at: ${RUNTIME_ENV_FILE}"
else
  echo "Env file mode: ephemeral (not persisted to disk)"
  echo "Tip: rerun this script before manual compose lifecycle commands requiring env interpolation."
fi
echo "Dashboard URL: http://localhost:${APP_PORT}"
