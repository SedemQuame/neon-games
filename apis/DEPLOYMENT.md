# GameHub API — Deployment Plan
> **Version:** 1.0 | **Updated:** February 2026

---

## Table of Contents
1. [Folder Structure](#1-folder-structure)
2. [Quick Start (Local)](#2-quick-start-local)
3. [Environment Variables Reference](#3-environment-variables-reference)
4. [Service Startup Order](#4-service-startup-order)
5. [Deployment Stages](#5-deployment-stages)
6. [Production Deployment (AWS)](#6-production-deployment-aws)
7. [Scaling Playbook](#7-scaling-playbook)
8. [Rollback Procedure](#8-rollback-procedure)

---

## 1. Folder Structure

```
apis/
├── auth-service/              # User auth, JWT, KYC
│   ├── cmd/main.go
│   ├── internal/
│   │   ├── config/config.go   # Env var loading
│   │   ├── handler/           # HTTP route handlers
│   │   └── middleware/        # JWT validation
│   └── Dockerfile
│
├── game-session-service/      # WS session relay to Deriv
│   ├── cmd/main.go
│   ├── internal/
│   │   ├── config/
│   │   ├── handler/           # REST + WebSocket handlers
│   │   └── session/           # Session manager + Kafka producer
│   └── Dockerfile
│
├── payment-gateway/           # Crypto + MoMo payment processing
│   ├── cmd/main.go
│   ├── internal/
│   │   ├── config/
│   │   ├── handler/           # MoMo initiation, webhook receivers
│   │   ├── middleware/        # HMAC verification, IP whitelist
│   │   └── webhook/           # Provider-specific logic
│   └── Dockerfile
│
├── wallet-service/            # Ledger, balances, withdrawals, leaderboard
│   ├── cmd/main.go
│   ├── internal/
│   │   ├── config/
│   │   ├── handler/
│   │   └── ledger/            # Append-only ledger + balance reservation
│   └── Dockerfile
│
├── trader-pool/               # Deriv account pool manager
│   ├── cmd/main.go
│   ├── internal/
│   │   ├── config/
│   │   └── pool/              # WS account pool, sweeper, health checks
│   └── Dockerfile
│
├── infra/
│   ├── nginx/nginx.conf       # Reverse proxy + rate limiting
│   └── mongo/init-replica.js  # Replica set + app user init
│
├── docker-compose.yml         # Full orchestration
├── Makefile                   # Developer commands
├── .env.example               # Environment variable template
└── DEPLOYMENT.md              # This file
```

---

## 2. Quick Start (Local)

### Prerequisites
- Docker Desktop ≥ 4.x
- `make` (pre-installed on macOS)
- `openssl` (pre-installed on macOS)

### Steps

```bash
# 1. Navigate to the apis directory
cd GameHub/apis

# 2. First-time setup: creates .env and generates JWT key pair
make setup

# 3. Fill in your credentials
nano .env
#  - Set DERIV_APP_ID
#  - Set PAYSTACK_SECRET_KEY, TATUM_API_KEY, etc.
#  - Change all *_PASSWORD values from defaults

# 4. Start everything
make up

# 5. Watch logs
make logs

# 6. Verify services are healthy
make ps
```

### Service URLs (local)
| Service | URL |
|---|---|
| NGINX (public gateway) | http://localhost:80 |
| Auth Service (direct) | http://localhost:8001 |
| Game Session Service | http://localhost:8002 |
| Payment Gateway | http://localhost:8003 |
| Wallet Service | http://localhost:8004 |
| Trader Pool | http://localhost:8005 |
| MongoDB | mongodb://localhost:27017 |
| Redis | redis://localhost:6379 |
| Kafka | localhost:9092 |
| Vault | http://localhost:8200 |

---

## 3. Environment Variables Reference

All services share a common `.env` file at `apis/.env`. The file is loaded by Docker Compose and injected into each container.

| Variable | Required | Description |
|---|---|---|
| `MONGO_URI` | ✅ | Full MongoDB connection URI with credentials |
| `MONGO_INITDB_ROOT_USERNAME` | ✅ | Root user for MongoDB init |
| `MONGO_INITDB_ROOT_PASSWORD` | ✅ | Root password for MongoDB init |
| `REDIS_ADDR` | ✅ | `host:port` of Redis |
| `REDIS_PASSWORD` | ✅ | Redis AUTH password |
| `KAFKA_BROKERS` | ✅ | Comma-separated Kafka broker list |
| `VAULT_ADDR` | ✅ | HashiCorp Vault address |
| `VAULT_TOKEN` | Dev only | Dev root token. Use AppRole in prod. |
| `JWT_PRIVATE_KEY_PATH` | ✅ | Path to RS256 private key (in container) |
| `JWT_PUBLIC_KEY_PATH` | ✅ | Path to RS256 public key (in container) |
| `JWT_ACCESS_TTL_MINUTES` | ✅ | Access token TTL (default: 15) |
| `JWT_REFRESH_TTL_DAYS` | ✅ | Refresh token TTL (default: 7) |
| `DERIV_APP_ID` | ✅ | Your registered Deriv application ID |
| `DERIV_WS_URL` | ✅ | Deriv WebSocket endpoint |
| `PAYSTACK_SECRET_KEY` | ✅ | Paystack secret for MoMo charges |
| `PAYSTACK_WEBHOOK_SECRET` | ✅ | HMAC secret for Paystack webhooks |
| `TATUM_API_KEY` | ✅ | Tatum API key for blockchain monitoring |
| `TATUM_WEBHOOK_SECRET` | ✅ | HMAC secret for Tatum webhooks |
| `DERIV_ACCOUNT_1_TOKEN` | ✅ | Deriv API token for first pool account |
| `DERIV_ACCOUNT_2_TOKEN` | optional | Additional pool accounts |
| `APP_ENV` | ✅ | `development` or `production` |
| `LOG_LEVEL` | optional | `debug`, `info`, `warn`, `error` |

> **Rule:** Every variable with ✅ is validated at service startup via `config.Load()`. If it is missing, the service **refuses to start** — this prevents silent misconfiguration in production.

---

## 4. Service Startup Order

Docker Compose `depends_on` with `condition: service_healthy` enforces this order automatically:

```
1.  mongo          — Database
2.  mongo-init     — Replica set + user creation
3.  redis          — Session store
4.  zookeeper      — Kafka dependency
5.  kafka          — Event bus
6.  kafka-init     — Topic creation (runs once)
7.  vault          — Secret manager
8.  auth-service       ← depends on: mongo, redis, vault
9.  game-session-service ← depends on: mongo, redis, kafka
10. payment-gateway    ← depends on: mongo, redis, kafka, vault
11. wallet-service     ← depends on: mongo, kafka
12. trader-pool        ← depends on: redis, kafka, vault
13. nginx              ← depends on: all microservices
```

---

## 5. Deployment Stages

### Stage 1 — Development (Docker Compose, local machine)
- All services run in Docker Compose
- MongoDB in single-node replica set (required for transactions)
- Vault in dev mode (`VAULT_DEV_ROOT_TOKEN_ID`)
- No TLS — plain HTTP
- `.env` loaded directly

### Stage 2 — Staging (Docker Compose on a VPS / EC2)
```bash
# On the staging server
git clone https://github.com/SedemQuame/gamified-trader.git
cd gamified-trader/apis
cp .env.example .env
# Edit .env with staging credentials
make up
```
- Nginx configured with real domain + Let's Encrypt TLS (Certbot)
- MongoDB Atlas M10 (shared) cluster
- Real Deriv app ID but smaller account pool
- Webhook endpoints exposed and tested with real Paystack/Tatum events

### Stage 3 — Production (Kubernetes on EKS)
- See Section 6 below

---

## 6. Production Deployment (AWS)

### Infrastructure
```
Cloudflare (DNS + WAF + DDoS)
  └── AWS ALB (Application Load Balancer)
        └── Kubernetes Ingress (NGINX controller)
              ├── auth-service       (Deployment, 2 pods min)
              ├── game-session-svc   (Deployment, 4 pods min — high WS load)
              ├── payment-gateway    (Deployment, 2 pods min)
              ├── wallet-service     (Deployment, 2 pods min)
              └── trader-pool        (Deployment, 2 pods min)

External managed services:
  MongoDB Atlas   — M30 Replica Set (dedicated)
  ElastiCache     — Redis 7 (cluster mode)
  MSK             — Managed Kafka (3 brokers)
  HCP Vault       — HashiCorp Cloud Vault
```

### Kubernetes Deployment (per service)
```yaml
# Example: auth-service deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: auth-service
spec:
  replicas: 2
  selector:
    matchLabels:
      app: auth-service
  template:
    spec:
      containers:
        - name: auth-service
          image: ghcr.io/sedemquame/gamehub-auth:${IMAGE_SHA}
          envFrom:
            - secretRef:
                name: gamehub-secrets   # Kubernetes Secret (from Vault)
          readinessProbe:
            httpGet:
              path: /health
              port: 8001
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /health
              port: 8001
            initialDelaySeconds: 15
            periodSeconds: 20
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "256Mi"
```

### Secrets in Production
```bash
# Sync secrets from Vault to Kubernetes using External Secrets Operator:
kubectl apply -f k8s/external-secrets/gamehub-secrets.yaml

# Never use kubectl create secret with raw values in CI/CD pipelines.
# Always pull from Vault.
```

---

## 7. Scaling Playbook

| Signal | Action |
|---|---|
| Game session CPU > 70% | HPA adds game-session-service pods (max: 10) |
| Kafka `trade_orders` lag > 1000 | KEDA scales trader-pool pods |
| Kafka `game_outcomes` lag > 1000 | KEDA scales wallet-service pods |
| MongoDB p99 query > 500ms | Add read replica, review indexes |
| Redis memory > 70% | Increase node size or enable eviction policy |
| Any Deriv account balance < $500 | Manually top up and add to pool registry |

### Manual Scaling (Docker Compose)
```bash
# Scale game-session-service to 3 instances
docker compose up -d --scale game-session-service=3
```

---

## 8. Rollback Procedure

### Docker Compose
```bash
# Roll back to a previous image tag
IMAGE_TAG=abc1234 docker compose up -d auth-service
```

### Kubernetes (ArgoCD)
```bash
# Roll back to the previous healthy deployment
argocd app rollback gamehub-auth
```

### Database Rollback
- The ledger collection is **append-only** — no destructive rollbacks possible by design.
- If a bug caused incorrect ledger entries, a **compensating entry** is written (credit to reverse a bad debit, or vice versa).
- All compensating entries include `source: "CORRECTION"` and a `reference` linking to the original entry and incident ticket.

---

*Always test staging before production. Always verify health endpoints after any deployment.*
