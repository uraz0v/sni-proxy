#!/bin/bash

# === START: [2026-10-28] Комплексный деплой: SNI-прокси + 3X-UI в Docker + автогенерация клиента ===
set -e

# Переход в директорию скрипта
cd "$(dirname "$0")"

DOMAIN_ARG="$1"

# 1. Проверка и генерация .env файла при его отсутствии
if [ ! -f ".env" ]; then
    echo "⚙️  Файл .env не найден. Запуск генерации параметров..."
    bash generate_env.sh "$DOMAIN_ARG"
fi

echo "Setting system timezone to Asia/Yekaterinburg..."
timedatectl set-timezone Asia/Yekaterinburg 2>/dev/null || echo "Failed to set timezone. Ignoring."

echo "Installing Docker if not present..."
docker compose version >/dev/null 2>&1 || (curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh && rm -f get-docker.sh)

echo "Updating lists..."
bash update_lists.sh

echo "Setting up SSL certificate via acme.sh..."
bash setup_ssl.sh

echo "Deploying SNI Proxy and 3X-UI containers..."
mkdir -p db
docker compose up -d --force-recreate

echo "Initializing 3X-UI and generating client configuration..."
python3 init_xui.py

echo "Setting up auto-update cron job on VPS..."
if ! crontab -l 2>/dev/null | grep -q "update_lists.sh"; then
    (crontab -l 2>/dev/null; echo "0 4 * * * cd /opt/sni-proxy && bash update_lists.sh >> /var/log/sni-proxy-update.log 2>&1") | crontab -
    echo "Cron job added to run every day at 04:00."
else
    echo "Cron job already exists."
fi
# === END: [2026-10-28] Комплексный деплой: SNI-прокси + 3X-UI в Docker + автогенерация клиента ===
