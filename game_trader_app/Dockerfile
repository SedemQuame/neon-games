# --- Stage 1: Build Flutter web app ---
FROM ghcr.io/cirruslabs/flutter:latest AS builder

WORKDIR /app

# Copy dependency files first for layer caching
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

# Copy the rest of the source
COPY . .

# Build arguments for the API base URL (injected at build time)
ARG GAMEHUB_BASE_URL=https://neon-games-production.up.railway.app
RUN flutter build web --release --dart-define=GAMEHUB_BASE_URL=${GAMEHUB_BASE_URL}

# --- Shared nginx runtime setup ---
FROM nginx:alpine AS nginx-base

# Remove default nginx config
RUN rm /etc/nginx/conf.d/default.conf

# Copy our nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Railway provides PORT env var; default to 80
ENV PORT=80

# Substitute $PORT into nginx config at runtime
CMD sh -c "envsubst '\$PORT' < /etc/nginx/conf.d/default.conf > /tmp/nginx.conf && mv /tmp/nginx.conf /etc/nginx/conf.d/default.conf && nginx -g 'daemon off;'"

EXPOSE 80

# --- Stage 2a: Serve a prebuilt local build/web directory ---
FROM nginx-base AS prebuilt

COPY build/web /usr/share/nginx/html

# --- Stage 2b: Default runtime (build inside Docker, then serve) ---
FROM nginx-base

COPY --from=builder /app/build/web /usr/share/nginx/html
