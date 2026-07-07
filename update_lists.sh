#!/bin/bash
cd /opt/sni-proxy || exit
echo "Fetching latest updates from Git repository..."
git fetch origin main

LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main)

if [ "$LOCAL" != "$REMOTE" ]; then
    echo "Changes detected. Pulling..."
    git pull origin main
    echo "Restarting docker container..."
    docker compose restart sni-proxy || docker restart sni_proxy || echo "Container sni_proxy not running."
else
    echo "No changes in repository. Nginx lists are up to date."
fi
