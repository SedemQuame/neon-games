FROM golang:1.25-alpine AS builder
ENV GOTOOLCHAIN=auto
WORKDIR /src
RUN apk add --no-cache ca-certificates
COPY . .
RUN set -eux; \
    service_dir="/src"; \
    if [ ! -f "$service_dir/go.mod" ]; then service_dir="/src/apis/game-session-service"; fi; \
    test -f "$service_dir/go.mod"; \
    cd "$service_dir"; \
    go mod download; \
    CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o /game-session-service ./cmd/main.go

FROM gcr.io/distroless/static-debian12
COPY --from=builder /game-session-service /game-session-service
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
EXPOSE 8002
USER nonroot:nonroot
ENTRYPOINT ["/game-session-service"]
