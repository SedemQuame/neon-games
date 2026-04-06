# GameHub Backend Infrastructure Deployment Strategy for Railway

## Executive Recommendation

Deploy GameHub to Railway with a public gateway service and private internal services.

Recommended production shape:

- Railway project for app runtime
- Railway environments for `staging` and `production`
- One public `api-gateway` service on Railway
- Private Railway services for:
  - `auth-service`
  - `game-session-service`
  - `payment-gateway`
  - `wallet-service`
  - `trader-pool`
  - `redis`
- External MongoDB Atlas replica set for MongoDB

Do not deploy the current backend as separate public Railway services behind separate domains. The Flutter client uses a single base URL, so the clean Railway fit is a public reverse proxy plus private microservices.

## Why Railway Can Work For This Repo

The backend already fits Railway's service model reasonably well:

- each Go service already has its own Dockerfile
- all services expose `/health`
- internal service URLs are environment-driven
- the system already separates stateless services from stateful infrastructure

The current backend also has constraints that directly shape the Railway plan:

- the client assumes one API base URL via `ApiClient`, so a public gateway is needed instead of per-service public domains
- `wallet-service` uses MongoDB transactions, so MongoDB must run as a replica set
- `game-session-service` and `payment-gateway` use Redis-backed messaging for WebSocket fanout, which makes multi-replica Railway deployment feasible
- `trader-pool` keeps Deriv account load state in memory, so it should remain a single replica initially
- the codebase uses Redis queues and PubSub, not Kafka
- the codebase does not actually load secrets from Vault at runtime

## Railway Topology

### Public Service

`api-gateway`

Responsibilities:

- terminates public HTTP and WebSocket traffic
- preserves the current single-base-URL app contract
- routes:
  - `/api/v1/auth/*` -> `auth-service`
  - `/api/v1/games/*` -> `game-session-service`
  - `/api/v1/payments/*` -> `payment-gateway`
  - `/api/v1/wallet/*` -> `wallet-service`
  - `/api/v1/leaderboard/*` -> `wallet-service`
  - `/ws` -> `game-session-service`
  - `/ws/payments` -> `payment-gateway`
  - `/webhooks/payment/*` -> `payment-gateway`

Recommended domains:

- `api.gamehub.io`
- optional second domain on the same gateway service: `hooks.gamehub.io`

### Private Railway Services

`auth-service`

- private
- 2 replicas in production

`game-session-service`

- private
- 2 replicas in production to start
- WebSocket traffic enters through the gateway

`payment-gateway`

- private
- 2 replicas in production to start
- handles both user payment APIs and provider webhooks

`wallet-service`

- private
- 2 replicas in production to start
- system of record for balances and ledger entries

`trader-pool`

- private
- 1 replica in both staging and initial production
- keep singleton until Deriv account coordination is externalized from process memory

`redis`

- private
- persistent volume attached
- used for:
  - trade order queue
  - PubSub
  - session locks
  - leaderboard cache

## MongoDB Strategy

Use MongoDB Atlas, not Railway's default MongoDB template, for production.

Reason:

- the wallet service wraps balance and ledger mutations in MongoDB transactions
- MongoDB transactions require replica set support
- the app is already configured around replica-set Mongo in local development

Recommended approach:

- staging: small Atlas replica set
- production: dedicated Atlas replica set with automated backups and alerting

## Redis Strategy

For staging, Railway Redis is acceptable.

For production, there are two viable options:

1. simplest: Railway Redis with a persistent volume
2. safer: external managed Redis

If the goal is fastest launch on Railway, start with Railway Redis and treat it as an operational risk you may later replace. Redis in this system is important because it carries order queuing, locks, and WebSocket event delivery.

## What To Remove From The Current Stack

Do not deploy these local-only components to Railway:

- local Docker Compose orchestration
- local Mongo container pair (`mongo` + `mongo-init`)
- local Vault container
- Kafka assumptions from old docs

The Railway deployment should be based on standalone services, not the local Compose control plane.

## Required App Changes Before Railway Production

These are the concrete blockers and hardening items for Railway deployment:

1. Keep the public gateway pattern.
- the app uses one base URL, so Railway should expose one public gateway service
- the gateway config must cover payment WebSockets and payment webhooks

2. Replace file-only JWT key handling.
- services currently expect PEM files on disk
- on Railway, prefer environment-based secret loading or a startup bootstrap that materializes key files

3. Fail closed in production.
- `trader-pool` must refuse to start in production if Deriv credentials are missing
- `trader-pool` must refuse production simulation mode unless explicitly allowed

4. Plan for Railway startup ordering.
- Railway does not give Docker Compose style `depends_on` semantics
- deploy Redis and Atlas connectivity first, then application services
- keep restart policies enabled because current services fail fast if dependencies are unavailable on boot

5. Rotate committed secrets.
- sample config currently contains credentials and credential-like values that should be treated as exposed
- rotate provider keys before any public deployment

6. Keep `trader-pool` single replica at first.
- it tracks Deriv account concurrency in process memory
- multiple replicas would coordinate poorly until that state moves to Redis or another shared store

## Railway Variable Strategy

Set explicit `PORT` values per service so internal URLs stay stable:

- `api-gateway` -> `PORT=80`
- `auth-service` -> `PORT=8001`
- `game-session-service` -> `PORT=8002`
- `payment-gateway` -> `PORT=8003`
- `wallet-service` -> `PORT=8004`
- `trader-pool` -> `PORT=8005`
- `redis` -> default Redis port

Key internal service variables:

- `AUTH_SERVICE_URL=http://auth-service.railway.internal:8001`
- `WALLET_SERVICE_URL=http://wallet-service.railway.internal:8004`
- `TRADER_POOL_URL=http://trader-pool.railway.internal:8005`
- `REDIS_ADDR=redis.railway.internal:6379`

Key external service variables:

- `MONGO_URI=<atlas replica set connection string>`
- provider credentials
- Deriv credentials
- JWT material
- webhook secrets

## Deployment Order On Railway

### Stage 1: Staging Foundation

1. Create a Railway project.
2. Create `staging` and `production` environments.
3. Provision the `redis` service on Railway.
4. Provision MongoDB Atlas and create the staging database user and network access rules.
5. Deploy private services:
   - `auth-service`
   - `wallet-service`
   - `trader-pool`
   - `game-session-service`
   - `payment-gateway`
6. Deploy the public `api-gateway`.
7. Attach a Railway domain first, then the real custom domain.
8. Validate:
   - guest auth
   - wallet balance
   - game WebSocket
   - payment WebSocket
   - webhook callback processing

### Stage 2: Production Cutover

1. Create production secrets and rotate all provider keys.
2. Use MongoDB Atlas production connection details.
3. If Atlas access is IP-restricted, enable Railway static outbound IPs for the services that connect to Atlas.
4. Scale:
   - `api-gateway`: 2 replicas
   - `auth-service`: 2 replicas
   - `game-session-service`: 2 replicas
   - `payment-gateway`: 2 replicas
   - `wallet-service`: 2 replicas
   - `trader-pool`: 1 replica
5. Switch custom domains to production.
6. Run smoke tests before opening traffic fully.

## Observability And Operations On Railway

Minimum setup:

- configure `/health` health checks on every service
- use Railway logs per service
- set alerting outside Railway for:
  - public uptime
  - webhook failures
  - payment processing errors
  - Redis memory pressure
  - Atlas connection failures

Important operational note:

- treat Railway health checks as deployment gates, not continuous uptime monitoring

## Scaling Guidance

Safe to scale horizontally:

- `api-gateway`
- `auth-service`
- `game-session-service`
- `payment-gateway`
- `wallet-service`

Do not scale yet:

- `trader-pool`

Potential next refactor before scaling `trader-pool`:

- move Deriv account lease and in-flight tracking into Redis

## Recommended Immediate Next Actions

1. Use Railway for app services, but keep MongoDB on Atlas from day one.
2. Keep a single public gateway service instead of exposing every microservice directly.
3. Finish Railway hardening:
   - JWT secret loading
   - production startup guards
   - secret rotation
4. Deploy staging on Railway first.
5. Prove the full login, wallet, game, deposit, and webhook loop before production cutover.
