FROM golang:1.25-alpine AS builder

ENV GOTOOLCHAIN=auto

WORKDIR /src

RUN apk add --no-cache ca-certificates

COPY . .

RUN set -eux; \
    mkdir -p /out/bin; \
    for service_dir in auth-service game-session-service payment-gateway wallet-service trader-pool gateway; do \
        cd "/src/${service_dir}"; \
        if [ -f go.mod ]; then \
            go mod download; \
        fi; \
        CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o "/out/bin/${service_dir}" ./cmd/main.go; \
    done

FROM redis:7-alpine

RUN apk add --no-cache bash ca-certificates tini

WORKDIR /app

COPY --from=builder /out/bin/ /app/bin/
COPY scripts/start-all.sh /app/start-all.sh

RUN chmod +x /app/start-all.sh && mkdir -p /app/secrets /var/lib/redis

EXPOSE 80 8001 8002 8003 8004 8005

ENTRYPOINT ["/sbin/tini", "--", "/app/start-all.sh"]
