FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY apis/wallet-service/go.mod apis/wallet-service/go.sum ./
RUN go mod download
COPY apis/wallet-service/ ./
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o /wallet-service ./cmd/main.go

FROM gcr.io/distroless/static-debian12
COPY --from=builder /wallet-service /wallet-service
EXPOSE 8004
USER nonroot:nonroot
ENTRYPOINT ["/wallet-service"]
