# =============================================================================
# Multi-stage Go build — distroless final image (no shell, minimal attack surface)
# =============================================================================

FROM golang:1.22-alpine AS builder

WORKDIR /app

# Cache dependencies first (only re-downloaded when go.mod/go.sum change)
COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o /auth-service ./cmd/main.go

# --- Final image ---
FROM gcr.io/distroless/static-debian12

COPY --from=builder /auth-service /auth-service

EXPOSE 8001

USER nonroot:nonroot

ENTRYPOINT ["/auth-service"]
