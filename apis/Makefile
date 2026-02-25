# Makefile — Glory Grid API Orchestration
# Usage: make <target>

.PHONY: help setup up down logs build restart clean ps

# Default target
help:
	@echo ""
	@echo "Glory Grid API — Available commands:"
	@echo ""
	@echo "  make setup     — First-time setup: copy .env, generate JWT keys"
	@echo "  make up        — Start all services (build if needed)"
	@echo "  make down      — Stop all services"
	@echo "  make build     — Rebuild all service images"
	@echo "  make restart   — Restart a specific service: make restart svc=auth-service"
	@echo "  make logs      — Tail logs for all services"
	@echo "  make logs-svc  — Tail logs for one service: make logs-svc svc=wallet-service"
	@echo "  make ps        — Show running container status"
	@echo "  make clean     — Remove all containers and volumes (WARNING: deletes data)"
	@echo ""

setup:
	@echo "→ Copying .env.example to .env..."
	@[ -f .env ] && echo "  .env already exists, skipping." || cp .env.example .env
	@echo "→ Generating RS256 JWT key pair..."
	@mkdir -p secrets
	@[ -f secrets/jwt_private.pem ] || openssl genrsa -out secrets/jwt_private.pem 4096
	@[ -f secrets/jwt_public.pem  ] || openssl rsa -in secrets/jwt_private.pem -pubout -out secrets/jwt_public.pem
	@echo "✅ Setup complete. Edit .env with your real credentials before running 'make up'."

up:
	@echo "→ Starting all Glory Grid services..."
	docker compose up -d --build
	@echo "✅ All services started. Run 'make logs' to watch output."

down:
	docker compose down

build:
	docker compose build --no-cache

restart:
	docker compose restart $(svc)

logs:
	docker compose logs -f --tail=100

logs-svc:
	docker compose logs -f --tail=100 $(svc)

ps:
	docker compose ps

clean:
	@echo "⚠️  This will delete all containers and volumes (MongoDB data, Redis, Kafka)."
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ]
	docker compose down -v --remove-orphans
