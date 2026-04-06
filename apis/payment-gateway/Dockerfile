FROM golang:1.22-alpine AS builder
WORKDIR /src
RUN apk add --no-cache ca-certificates
COPY . .
RUN set -eux; \
    service_dir="/src"; \
    if [ ! -f "$service_dir/go.mod" ]; then service_dir="/src/apis/payment-gateway"; fi; \
    test -f "$service_dir/go.mod"; \
    cd "$service_dir"; \
    go mod download; \
    CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o /payment-gateway ./cmd/main.go

FROM gcr.io/distroless/static-debian12
COPY --from=builder /payment-gateway /payment-gateway
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
EXPOSE 8003
USER nonroot:nonroot
ENTRYPOINT ["/payment-gateway"]
