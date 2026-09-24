#!/usr/bin/env bash
set -euo pipefail

cd /home/fond/xr-gateway
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  echo 'Server repository has tracked changes; deployment stopped.' >&2
  exit 1
fi

git pull --ff-only
if ! grep -Eq '^REDIS_PASSWORD=.+$' deploy/.env; then
  echo 'Set REDIS_PASSWORD in deploy/.env before publishing Redis to the LAN.' >&2
  exit 1
fi

compose=(sudo docker compose -f deploy/docker-compose.local.yml -f deploy/docker-compose.custom.yml -f deploy/docker-compose.lan.yml)
"${compose[@]}" config --quiet
mkdir -p /home/fond/backups
umask 077
backup="/home/fond/backups/sub2api-before-deploy-$(date +%Y%m%d-%H%M%S).dump"
"${compose[@]}" exec -T postgres sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -Fc -U "$POSTGRES_USER" "$POSTGRES_DB"' > "$backup"
test -s "$backup"

sudo docker image tag xr-gateway:local "xr-gateway:pre-deploy-$(date +%Y%m%d-%H%M%S)"
"${compose[@]}" build sub2api
"${compose[@]}" up -d --no-build
"${compose[@]}" ps
