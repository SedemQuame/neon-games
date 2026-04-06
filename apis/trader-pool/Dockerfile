FROM golang:1.25-alpine AS builder
ENV GOTOOLCHAIN=auto
WORKDIR /src
COPY . .
RUN set -eux; \
    service_dir="/src"; \
    if [ ! -f "$service_dir/go.mod" ]; then service_dir="/src/apis/trader-pool"; fi; \
    test -f "$service_dir/go.mod"; \
    cd "$service_dir"; \
    go mod download; \
    CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o /trader-pool ./cmd/main.go

FROM gcr.io/distroless/static-debian12
COPY --from=builder /trader-pool /trader-pool
EXPOSE 8005
USER nonroot:nonroot
ENTRYPOINT ["/trader-pool"]
