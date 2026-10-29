FROM nginx:1.27-alpine
COPY app/nginx.conf /etc/nginx/conf.d/default.conf
COPY app/docker-entrypoint.d/30-oidc-config.sh /docker-entrypoint.d/30-oidc-config.sh
COPY app/build/web /usr/share/nginx/html
EXPOSE 80
