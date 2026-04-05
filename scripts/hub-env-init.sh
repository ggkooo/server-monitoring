#!/usr/bin/env bash
set -euo pipefail

OUTPUT_FILE=".env.hub"
FORCE="false"
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

usage() {
  cat <<'EOF'
Usage: ./scripts/hub-env-init.sh [options]

Create or update .env.hub with randomly generated REVERB credentials and Prometheus auth.

Security note:
  This script persists secrets to disk. Prefer scripts/hub-bootstrap.sh for
  ephemeral credentials (no persisted env file by default).

Options:
  --output <path>          Output env file path (default: .env.hub)
  --dockerhub-user <user>  Docker Hub username (default: giordanoberwig)
  --image-tag <tag>        Image tag (default: v1.0.1)
  --app-port <port>        Host app port (default: 8991)
  --network-name <name>    Docker network name (default: server-monitoring-network)
  --prom-user <username>   Prometheus basic auth username (default: auto-generated)
  --prom-pass <password>   Prometheus basic auth password (default: auto-generated)
  --prom-pass-hash <hash>  Prometheus bcrypt hash (default: auto-generated from password)
  --prom-pass-hash-b64 <b64>
                           Prometheus bcrypt hash in base64 (default: derived)
  --reverb-app-id <id>     Reverb app ID (default: auto-generated)
  --reverb-app-key <key>   Reverb app key (default: auto-generated)
  --reverb-app-secret <s>  Reverb app secret (default: auto-generated)
  --force                  Overwrite output file if it does not exist from template
  -h, --help               Show this help message

Examples:
  ./scripts/hub-env-init.sh
  ./scripts/hub-env-init.sh --prom-user admin --prom-pass 'StrongPass!123'
  ./scripts/hub-env-init.sh --dockerhub-user myuser --image-tag v1.0.1
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      OUTPUT_FILE="${2:?Missing value for --output}"
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
    --force)
      FORCE="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

random_alnum() {
  local length="$1"
  local result=""

  while [[ ${#result} -lt "$length" ]]; do
    # `tr | head` can raise SIGPIPE under pipefail; ignore that partial-pipe status.
    result+="$(tr -dc 'a-z0-9' </dev/urandom | head -c "$length" || true)"
  done

  printf '%s' "${result:0:length}"
}

random_id() {
  shuf -i 100000-999999 -n 1
}

generate_bcrypt_hash() {
  local password="$1"

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

if [[ ! -f "$OUTPUT_FILE" ]]; then
  if [[ -f ".env.hub.example" ]]; then
    cp .env.hub.example "$OUTPUT_FILE"
  else
    : >"$OUTPUT_FILE"
  fi
elif [[ "$FORCE" == "true" && -f ".env.hub.example" ]]; then
  cp .env.hub.example "$OUTPUT_FILE"
fi

[[ -z "$REVERB_APP_ID" ]]     && REVERB_APP_ID="$(random_id)"
[[ -z "$REVERB_APP_KEY" ]]    && REVERB_APP_KEY="$(random_alnum 20)"
[[ -z "$REVERB_APP_SECRET" ]] && REVERB_APP_SECRET="$(random_alnum 20)"

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

if [[ -z "$PROMETHEUS_USERNAME" ]]; then
  PROMETHEUS_USERNAME="prom_$(random_alnum 10)"
fi

upsert_env_var "$OUTPUT_FILE" "DOCKERHUB_USER" "$DOCKERHUB_USER"
upsert_env_var "$OUTPUT_FILE" "IMAGE_TAG" "$IMAGE_TAG"
upsert_env_var "$OUTPUT_FILE" "APP_PORT" "$APP_PORT"
upsert_env_var "$OUTPUT_FILE" "DOCKER_NETWORK_NAME" "$DOCKER_NETWORK_NAME"
upsert_env_var "$OUTPUT_FILE" "APP_ENV" "$APP_ENV"
upsert_env_var "$OUTPUT_FILE" "APP_DEBUG" "$APP_DEBUG"
upsert_env_var "$OUTPUT_FILE" "APP_URL" "$APP_URL"
upsert_env_var "$OUTPUT_FILE" "REVERB_APP_ID" "$REVERB_APP_ID"
upsert_env_var "$OUTPUT_FILE" "REVERB_APP_KEY" "$REVERB_APP_KEY"
upsert_env_var "$OUTPUT_FILE" "REVERB_APP_SECRET" "$REVERB_APP_SECRET"
upsert_env_var "$OUTPUT_FILE" "PROMETHEUS_USERNAME" "$PROMETHEUS_USERNAME"
upsert_env_var "$OUTPUT_FILE" "PROMETHEUS_PASSWORD" "$PROMETHEUS_PASSWORD"
upsert_env_var "$OUTPUT_FILE" "PROMETHEUS_PASSWORD_HASH" "$PROMETHEUS_PASSWORD_HASH"
upsert_env_var "$OUTPUT_FILE" "PROMETHEUS_PASSWORD_HASH_B64" "$PROMETHEUS_PASSWORD_HASH_B64"

cat <<EOF
Updated ${OUTPUT_FILE} with fresh hub credentials:
REVERB_APP_ID=${REVERB_APP_ID}
REVERB_APP_KEY=${REVERB_APP_KEY}
REVERB_APP_SECRET=${REVERB_APP_SECRET}
PROMETHEUS_USERNAME=${PROMETHEUS_USERNAME}
PROMETHEUS_PASSWORD=${PROMETHEUS_PASSWORD}

Run:
docker compose --env-file ${OUTPUT_FILE} -f docker-compose.hub.yml up -d
EOF
