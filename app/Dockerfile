FROM node:22-alpine AS auth
WORKDIR /workspace/web-auth
COPY web-auth/package*.json ./
RUN npm ci
COPY web-auth/src ./src
RUN npm run build

FROM ghcr.io/cirruslabs/flutter:stable AS build
WORKDIR /workspace/app
COPY app/ ./
COPY --from=auth /workspace/app/web/auth.js ./web/auth.js
RUN flutter pub get && flutter build web --release

FROM nginx:1.27-alpine
COPY app/nginx.conf /etc/nginx/conf.d/default.conf
COPY app/docker-entrypoint.d/30-oidc-config.sh /docker-entrypoint.d/30-oidc-config.sh
COPY --from=build /workspace/app/build/web /usr/share/nginx/html
EXPOSE 80
