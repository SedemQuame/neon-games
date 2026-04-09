# Glory Grid API — Deployment Notes
> **Updated:** April 9, 2026

## Overview

The backend now runs as a single container built from [Dockerfile](/Users/sedemquame/Documents/Commercial/self/games/GameHub/apis/Dockerfile). That image contains:

- `auth-service`
- `game-session-service`
- `payment-gateway`
- `wallet-service`
- `trader-pool`
- an internal Go gateway on port `80`
- embedded Redis for caching and PubSub

MongoDB is external and is injected through `MONGO_URI`.

## Folder Layout

```text
apis/
├── Dockerfile
├── docker-compose.yml
├── Makefile
├── .env.example
├── gateway/
│   └── cmd/main.go
├── scripts/
│   └── start-all.sh
├── auth-service/
├── game-session-service/
├── payment-gateway/
├── wallet-service/
└── trader-pool/
```

## Quick Start

```bash
cd GameHub/apis
make setup
# edit .env and supply your real Mongo / provider credentials
make up
make logs
```

Default local endpoints:

| Service | URL |
|---|---|
| Gateway | http://localhost:80 |
| Auth Service | http://localhost:8001 |
| Game Session Service | http://localhost:8002 |
| Payment Gateway | http://localhost:8003 |
| Wallet Service | http://localhost:8004 |
| Trader Pool | http://localhost:8005 |

Health endpoints:

- `GET /health`
- `GET /health/upstreams`

## Runtime Model

Startup happens inside one container:

1. `redis-server` starts on `127.0.0.1:6379`
2. Each Go service starts on its own port
3. The internal gateway binds to `GATEWAY_PORT` and proxies the public API paths

The gateway preserves these routes:

- `/api/v1/auth/*`
- `/api/v1/games/*`
- `/ws`
- `/ws/payments`
- `/api/v1/payments/*`
- `/webhooks/payment/*`
- `/api/v1/wallet/*`
- `/api/v1/leaderboard/*`

## Required Environment

At minimum, staging needs:

- `MONGO_URI`
- `REDIS_PASSWORD`
- `JWT_PRIVATE_KEY_PATH` or `JWT_PRIVATE_KEY_PEM`
- `JWT_PUBLIC_KEY_PATH` or `JWT_PUBLIC_KEY_PEM`
- `INTERNAL_SERVICE_KEY`
- whichever payment and Deriv credentials are required for the integrations you intend to enable

The default Compose setup mounts JWT files from `apis/infra/dev-secrets` into `/app/secrets`.

## Compose Usage

The Compose file now starts one service only:

```bash
docker compose up -d --build
```

That service exposes ports `80`, `8001`, `8002`, `8003`, `8004`, and `8005`.

## Plain Docker Usage

```bash
docker build -t gamehub-backend ./apis
docker run --rm \
  --env-file ./apis/.env \
  -v "$(pwd)"/apis/infra/dev-secrets:/app/secrets:ro \
  -p 80:80 -p 8001:8001 -p 8002:8002 -p 8003:8003 -p 8004:8004 -p 8005:8005 \
  gamehub-backend
```

## Staging Notes

- The single-container image is the intended staging path.
- MongoDB should point at Atlas or another managed replica set through `MONGO_URI`.
- nginx is no longer part of the backend stack.
- If you already terminate TLS at a platform edge or load balancer, forward traffic directly to the gateway port.
