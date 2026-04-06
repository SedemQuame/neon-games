FROM golang:1.25-alpine AS builder
ENV GOTOOLCHAIN=auto
WORKDIR /app
COPY apis/trader-pool/go.mod apis/trader-pool/go.sum ./
RUN go mod download
COPY apis/trader-pool/ ./
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o /trader-pool ./cmd/main.go

FROM gcr.io/distroless/static-debian12
COPY --from=builder /trader-pool /trader-pool
EXPOSE 8005
USER nonroot:nonroot
ENTRYPOINT ["/trader-pool"]
