#!/usr/bin/env sh
set -eu

destination=${1:-"backups/$(date -u +%Y%m%dT%H%M%SZ)"}
mkdir -p "$destination"

docker compose exec -T postgres sh -c 'pg_dump -U "$POSTGRES_USER" -Fc esma' > "$destination/esma.dump"
docker compose exec -T postgres sh -c 'pg_dump -U "$POSTGRES_USER" -Fc esma_keycloak' > "$destination/keycloak.dump"

storage_driver=$(docker compose exec -T api printenv STORAGE_DRIVER | tr -d '\r')
if [ "$storage_driver" = "local" ]; then
  docker compose exec -T api tar -C /data/images -czf - . > "$destination/images.tar.gz"
fi

echo "Backup written to $destination"
