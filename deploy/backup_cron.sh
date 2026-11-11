#!/usr/bin/env bash
# Nightly database + media backup on the VPS, 14 days kept.
# Install:  install -m 755 deploy/backup_cron.sh /usr/local/bin/peaksell-backup
#           echo '30 3 * * * root /usr/local/bin/peaksell-backup' > /etc/cron.d/peaksell-backup
set -euo pipefail
APP_DIR="${APP_DIR:-/opt/peaksell-studio}"
DEST="${DEST:-/var/backups/peaksell}"
STAMP="$(date +%F)"
cd "$APP_DIR"
mkdir -p "$DEST"
docker compose -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.tunnel.yml \
  exec -T postgres pg_dump -U postgres -Fc peaksell > "$DEST/peaksell-$STAMP.dump"
docker run --rm -v "$(basename "$APP_DIR")_media_data:/m:ro" -v "$DEST:/out" alpine:3.20 \
  tar czf "/out/media-$STAMP.tgz" -C /m .
cp .env "$DEST/env-$STAMP" && chmod 600 "$DEST"/*
find "$DEST" -type f -mtime +14 -delete
