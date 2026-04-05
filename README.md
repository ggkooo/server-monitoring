# server-monitoring 🚀

A production-style, containerized server monitoring stack with real-time dashboards over end-to-end encrypted WebSocket.

This repository orchestrates a full observability flow:

- Metrics collection from host and processes
- Time-series storage and querying
- Real-time broadcast pipeline
- Web dashboard streaming live metrics over WSS

## Overview 🧭

The stack combines:

- Prometheus for scraping and querying metrics
- Node Exporter for host-level metrics
- Process Exporter for per-process metrics
- Laravel + Reverb backend for metrics aggregation and broadcasting
- React + Nginx frontend for visualization

Current websocket security flow:

- Browser -> Nginx: `wss://` (TLS at edge) 🔒
- Nginx -> Reverb: `wss://` (TLS on internal Docker hop) 🔐

## Repository Structure 📁

- `docker-compose.yml`: Root orchestration for all services
- `.env` / `.env.example`: Root frontend build-time websocket variables
- `monitoring/`: Prometheus and exporter configuration
- `b-server-monitoring/`: Laravel backend (Reverb, scheduler, metrics services)
- `f-server-monitoring/`: React frontend (dashboard UI + Nginx reverse proxy)

## Architecture 🏗️

1. `node-exporter` exposes host metrics (`/proc`, `/sys`, filesystem).
2. `process-exporter` exposes process metrics grouped by process name.
3. `prometheus` scrapes both exporters every 5 seconds.
4. Backend scheduler runs periodic metrics broadcast commands.
5. Backend queries Prometheus and publishes `metrics.updated` through Reverb.
6. Frontend subscribes to websocket channel and updates UI in real time.

## Services and Ports 🌐

- Frontend (Nginx): `80`, `443`
- Backend (Laravel Reverb): internal `8080`
- Prometheus: internal `9090`
- Node Exporter: internal `9100`
- Process Exporter: internal `9256`

The frontend is the only service mapped to host ports by default.

## Prerequisites ✅

- Docker Engine
- Docker Compose v2
- Linux host with `/proc` and `/sys` available to exporter containers

## Quick Start ⚡

1. Clone repository.
2. Configure environment files.
3. Build and start stack.
4. Open dashboard.

### 1) Configure root environment 🧪

Create root `.env` from example:

```bash
cp .env.example .env
```

Set these values:

- `VITE_METRICS_WS_URL`
- `VITE_METRICS_CHANNEL`

Default URL format:

```env
VITE_METRICS_WS_URL=wss://localhost/app/<REVERB_APP_KEY>?protocol=7&client=js&version=8.4.0&flash=false
VITE_METRICS_CHANNEL=metrics
```

Important: `<REVERB_APP_KEY>` must match the backend Reverb app key.

### 2) Configure backend environment 🛠️

```bash
cp b-server-monitoring/.env.example b-server-monitoring/.env
```

At minimum, set:

- `REVERB_APP_ID`
- `REVERB_APP_KEY`
- `REVERB_APP_SECRET`
- `PROMETHEUS_BASE_URL` (default internal: `http://prometheus:9090`)

TLS-related backend defaults are already configured for containerized local usage.

### 3) Build and run 🐳

```bash
docker compose build
docker compose up -d
```

### 4) Check status 👀

```bash
docker compose ps
```

### 5) Open dashboard 📊

- `https://localhost`

You may see a browser warning in local environments due to self-signed certificates.

## TLS and WSS Notes 🔐

### Local/dev behavior 🧩

- Frontend Nginx uses a generated self-signed certificate.
- Backend Reverb uses generated self-signed certificate when missing.
- Nginx proxies websocket upstream to backend with TLS.
- Nginx upstream verification is disabled in dev (`proxy_ssl_verify off`) to allow self-signed backend certs.

### Production recommendations 🏭

- Use a trusted public certificate on frontend Nginx (for browser trust).
- Use trusted internal certificate for backend Reverb.
- Enable strict upstream/backend certificate validation.
- Disable self-signed behavior in backend TLS settings.

## Metrics Configuration 📈

Prometheus scrape configuration is in:

- `monitoring/prometheus.yml`

Current scrape interval: `5s`.

Process grouping pattern is in:

- `monitoring/process-config.yml`

Prometheus web auth configuration:

- `monitoring/web-config.yml`

## Common Operations 🧰

## Docker Hub Distribution 📦

You can publish prebuilt images so users only pull images and run the stack.

Default stable tag for Hub deployment: `v1.0.0`.

Publisher workflow:

1. Login to Docker Hub:

	docker login

2. Publish all images:

	./scripts/dockerhub-publish.sh <dockerhub-user> v1.0.0

This publishes:

- <dockerhub-user>/server-monitoring-frontend:v1.0.0
- <dockerhub-user>/server-monitoring-backend:v1.0.0
- <dockerhub-user>/server-monitoring-prometheus:v1.0.0
- <dockerhub-user>/server-monitoring-process-exporter:v1.0.0
- <dockerhub-user>/server-monitoring-edge-nginx:v1.0.0

Consumer workflow:

1. Quick download (server):

	mkdir -p ~/server-monitoring && cd ~/server-monitoring
	curl -fsSL https://raw.githubusercontent.com/ggkooo/server-monitoring/master/docker-compose.hub.yml -o docker-compose.hub.yml
	curl -fsSL https://raw.githubusercontent.com/ggkooo/server-monitoring/master/.env.hub.example -o .env.hub

2. Edit credentials in `.env.hub`:

	- REVERB_APP_ID
	- REVERB_APP_KEY
	- REVERB_APP_SECRET
	- PROMETHEUS_USERNAME
	- PROMETHEUS_PASSWORD

3. Pull and run:

	docker compose --env-file .env.hub -f docker-compose.hub.yml pull
	docker compose --env-file .env.hub -f docker-compose.hub.yml up -d

4. Follow logs:

	docker compose --env-file .env.hub -f docker-compose.hub.yml logs -f

3. Open dashboard (default port 8991):

	http://localhost:8991
	
   Or use your configured `APP_PORT` from `.env.hub`:
   
	http://your-server-ip:${APP_PORT}

Notes:

- Hub network name uses `server-monitoring-network` by default.
- You can override it with `DOCKER_NETWORK_NAME` in `.env.hub`.

### Rebuild after changes 🔄

```bash
docker compose down
docker compose build
docker compose up -d
```

### Follow logs 📜

```bash
docker compose logs -f backend
docker compose logs -f frontend
docker compose logs -f prometheus
```

### Stop stack 🛑

```bash
docker compose down
```

## Troubleshooting 🧯

### Dashboard does not receive live updates 📡

- Confirm backend and frontend containers are running.
- Verify websocket URL in root `.env` matches current Reverb key.
- Check frontend logs for websocket upgrade status (`101`).
- Check backend logs for Reverb startup and scheduler execution.

### Browser shows "Not Secure" ⚠️

- Expected in local setup with self-signed certs.
- For production, configure trusted certificates (for example, Let's Encrypt at edge).

### Prometheus data is missing 🧠

- Confirm `node-exporter` and `process-exporter` are up.
- Check Prometheus target health.
- Validate PromQL queries configured in backend `.env`.

## Development Workflow 🔁

This repository tracks frontend and backend as nested git repositories.

Typical workflow:

1. Create feature branch in each sub-repo when needed.
2. Commit backend/frontend changes in their own repositories.
3. Update root repo submodule pointers and root configs.
4. Commit root repository changes.

## Related Documentation 📚

- Backend details: `b-server-monitoring/README.md`
- Frontend details: `f-server-monitoring/README.md`

## License 📄

Please refer to licenses within subprojects as applicable.
