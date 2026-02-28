FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN apk add --no-cache ca-certificates && go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o /payment-gateway ./cmd/main.go

FROM gcr.io/distroless/static-debian12
COPY --from=builder /payment-gateway /payment-gateway
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
EXPOSE 8003
USER nonroot:nonroot
ENTRYPOINT ["/payment-gateway"]
