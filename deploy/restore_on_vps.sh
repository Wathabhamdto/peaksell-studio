#!/usr/bin/env bash
# Restore the PC bundle on the VPS and start PeakSell Studio behind the tunnel.
#
#   bash restore_on_vps.sh /root/peaksell-bundle
#
# The bundle dir must contain .env, peaksell.dump and media.tgz
# (made by deploy/export_from_pc.ps1). Without a bundle (fresh start), pass
# --fresh and put a ready .env in /opt/peaksell-studio/.env first.
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/Wathabhamdto/peaksell-studio.git}"
APP_DIR="${APP_DIR:-/opt/peaksell-studio}"
BUNDLE="${1:?usage: restore_on_vps.sh <bundle-dir> | --fresh}"
DC=(docker compose -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.tunnel.yml)

if [ ! -d "$APP_DIR/.git" ]; then
  git clone "$REPO_URL" "$APP_DIR"
else
  git -C "$APP_DIR" pull --ff-only
fi
cd "$APP_DIR"
PROJECT="$(basename "$APP_DIR")"

if [ "$BUNDLE" != "--fresh" ]; then
  install -m 600 "$BUNDLE/.env" .env
fi
[ -f .env ] || { echo "missing $APP_DIR/.env"; exit 1; }
grep -q '^CLOUDFLARE_TUNNEL_TOKEN=.\+' .env || { echo "CLOUDFLARE_TUNNEL_TOKEN empty in .env"; exit 1; }
grep -q '^POSTGRES_PASSWORD=.\+' .env || { echo "POSTGRES_PASSWORD empty in .env"; exit 1; }

echo "== Build images =="
"${DC[@]}" build

echo "== Start database =="
"${DC[@]}" up -d postgres
until "${DC[@]}" exec -T postgres pg_isready -U postgres >/dev/null 2>&1; do sleep 2; done

if [ "$BUNDLE" != "--fresh" ]; then
  echo "== Restore database =="
  # A brand-new volume was initialised with POSTGRES_PASSWORD from .env, matching DATABASE_URL.
  "${DC[@]}" cp "$BUNDLE/peaksell.dump" postgres:/tmp/peaksell.dump
  "${DC[@]}" exec -T postgres pg_restore -U postgres -d peaksell --clean --if-exists --no-owner /tmp/peaksell.dump || true
  "${DC[@]}" exec -T postgres psql -U postgres -d peaksell -c "select count(*) as users from accounts_user;"

  echo "== Restore media =="
  docker volume create "${PROJECT}_media_data" >/dev/null
  docker run --rm -v "${PROJECT}_media_data:/m" -v "$BUNDLE:/in:ro" alpine:3.20 sh -c "tar xzf /in/media.tgz -C /m"
fi

echo "== Start everything =="
"${DC[@]}" up -d
sleep 15
"${DC[@]}" ps
APP_HOST="$(grep '^ALLOWED_HOSTS=' .env | cut -d= -f2 | cut -d, -f1)"
curl -fsS -H "Host: $APP_HOST" -H "X-Forwarded-Proto: https" http://127.0.0.1:8000/health/ && echo " <- health OK"
