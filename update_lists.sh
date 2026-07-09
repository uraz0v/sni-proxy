#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
cd /opt/sni-proxy || exit

# Функция для вывода логов с временной меткой
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Fetching latest updates from Git repository..."
git fetch origin main

LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main)

if [ "$LOCAL" != "$REMOTE" ]; then
    log "Changes detected. Pulling..."
    git pull origin main
    log "Restarting docker container..."
    docker compose restart sni-proxy || docker restart sni_proxy || log "Container sni_proxy not running."
    log "Update and restart complete."
else
    log "No changes in repository. Nginx lists are up to date."
fi
