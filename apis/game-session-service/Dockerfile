FROM golang:1.25-alpine AS builder
ENV GOTOOLCHAIN=auto
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o /game-session-service ./cmd/main.go

FROM gcr.io/distroless/static-debian12
COPY --from=builder /game-session-service /game-session-service
EXPOSE 8002
USER nonroot:nonroot
ENTRYPOINT ["/game-session-service"]
