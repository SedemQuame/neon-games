FROM nginx:1.25-alpine

COPY . /src

RUN set -eux; \
    template="/src/railway.conf.template"; \
    if [ ! -f "$template" ]; then template="/src/apis/infra/nginx/railway.conf.template"; fi; \
    test -f "$template"; \
    rm -f /etc/nginx/conf.d/default.conf; \
    mkdir -p /etc/nginx/templates; \
    cp "$template" /etc/nginx/templates/default.conf.template

EXPOSE 80
