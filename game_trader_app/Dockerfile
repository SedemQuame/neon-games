FROM nginx:alpine

# Remove default nginx config
RUN rm /etc/nginx/conf.d/default.conf

# Copy our nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy pre-built Flutter web app
COPY build/web /usr/share/nginx/html

# Railway provides PORT env var; default to 8080
ENV PORT=8080

# Substitute $PORT into nginx config at runtime
CMD sh -c "envsubst '\$PORT' < /etc/nginx/conf.d/default.conf > /tmp/nginx.conf && mv /tmp/nginx.conf /etc/nginx/conf.d/default.conf && nginx -g 'daemon off;'"

EXPOSE 8080
