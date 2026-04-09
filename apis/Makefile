# Makefile — Glory Grid all-in-one backend
# Usage: make <target>

.PHONY: help setup up down logs build restart clean ps logs-svc

COMPOSE := docker compose
SERVICE ?= gamehub-backend
KEY_DIR := infra/dev-secrets

help:
	@echo ""
	@echo "Glory Grid backend — Available commands:"
	@echo ""
	@echo "  make setup     — Copy .env, generate JWT keys for the single container"
	@echo "  make build     — Build the all-in-one backend image"
	@echo "  make up        — Start the backend container"
	@echo "  make down      — Stop the backend container"
	@echo "  make restart   — Restart the backend container"
	@echo "  make logs      — Tail backend logs"
	@echo "  make logs-svc  — Alias of make logs"
	@echo "  make ps        — Show container status"
	@echo "  make clean     — Remove the container and Redis volume"
	@echo ""

setup:
	@echo "→ Copying .env.example to .env..."
	@[ -f .env ] && echo "  .env already exists, skipping." || cp .env.example .env
	@echo "→ Generating RS256 JWT key pair in $(KEY_DIR)..."
	@mkdir -p $(KEY_DIR)
	@[ -f $(KEY_DIR)/jwt_private.pem ] || openssl genrsa -out $(KEY_DIR)/jwt_private.pem 4096
	@[ -f $(KEY_DIR)/jwt_public.pem  ] || openssl rsa -in $(KEY_DIR)/jwt_private.pem -pubout -out $(KEY_DIR)/jwt_public.pem
	@echo "✅ Setup complete. Edit .env before running 'make up'."

build:
	$(COMPOSE) build

up:
	@echo "→ Starting Glory Grid backend container..."
	$(COMPOSE) up -d --build
	@echo "✅ Backend started. Gateway is available on http://localhost:$${GATEWAY_PORT:-80}"

down:
	$(COMPOSE) down

restart:
	$(COMPOSE) restart $(SERVICE)

logs:
	$(COMPOSE) logs -f --tail=100 $(SERVICE)

logs-svc:
	$(COMPOSE) logs -f --tail=100 $(SERVICE)

ps:
	$(COMPOSE) ps

clean:
	@echo "⚠️  This will delete the backend container and Redis data volume."
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ]
	$(COMPOSE) down -v --remove-orphans
