#!/bin/bash
echo "Installing Docker if not present..."
docker compose version || docker-compose version || (curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh)

echo "Updating lists..."
bash update_lists.sh

echo "Deploying SNI Proxy..."
if docker compose version >/dev/null 2>&1; then
    docker compose up -d
else
    docker-compose up -d
fi
echo "✅ SNI Proxy successfully deployed and running on port 443!"

echo "Setting up auto-update cron job on VPS..."
if ! crontab -l 2>/dev/null | grep -q "update_lists.sh"; then
    (crontab -l 2>/dev/null; echo "0 4 * * * cd /opt/sni-proxy && bash update_lists.sh >> /var/log/sni-proxy-update.log 2>&1") | crontab -
    echo "Cron job added to run every day at 04:00."
else
    echo "Cron job already exists."
fi
