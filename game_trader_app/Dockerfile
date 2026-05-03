FROM ghcr.io/cirruslabs/flutter:stable AS builder

WORKDIR /app

# Pull dependencies first for better layer caching.
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

# Copy app sources and build fresh web artifacts for each image build.
COPY . .

ARG GAMEHUB_BASE_URL=http://127.0.0.1
RUN flutter build web --release --dart-define=GAMEHUB_BASE_URL=${GAMEHUB_BASE_URL}

FROM nginx:alpine

RUN rm /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/build/web /usr/share/nginx/html

ENV PORT=8080
CMD sh -c "envsubst '\$PORT' < /etc/nginx/conf.d/default.conf > /tmp/nginx.conf && mv /tmp/nginx.conf /etc/nginx/conf.d/default.conf && nginx -g 'daemon off;'"

EXPOSE 8080
