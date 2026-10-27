#!/bin/bash

# === START: [2026-10-28] Комплексный деплой: SNI-прокси + 3X-UI в Docker + автогенерация клиента ===
set -e
trap '' HUP

# Переход в директорию скрипта
cd "$(dirname "$0")"

DOMAIN_ARG="$1"

# Установка базовых утилит на чистой ОС
echo "Ensuring essential system packages are installed..."
if command -v dnf >/dev/null 2>&1; then
    dnf install -y git curl python3 openssl tar socat cronie >/dev/null 2>&1 || true
    systemctl enable --now crond 2>/dev/null || true
elif command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq git curl python3 openssl tar socat cron >/dev/null 2>&1 || true
    systemctl enable --now cron 2>/dev/null || true
fi

# Открытие портов HTTP (80) и HTTPS (443) в фаерволе
if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld 2>/dev/null; then
    echo "Opening HTTP and HTTPS in firewalld..."
    firewall-cmd --permanent --add-service=http --add-service=https >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
elif command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qw "active"; then
    echo "Opening HTTP and HTTPS in ufw..."
    ufw allow 80/tcp >/dev/null 2>&1 || true
    ufw allow 443/tcp >/dev/null 2>&1 || true
fi

# === START: [2026-10-28] Отключение службы Cockpit на RHEL/AlmaLinux/CentOS ===
# Cockpit по умолчанию слушает порт 9090 и расходует системные ресурсы
if systemctl is-active --quiet cockpit.socket 2>/dev/null || systemctl is-enabled --quiet cockpit.socket 2>/dev/null; then
    echo "Disabling and stopping Cockpit (port 9090)..."
    systemctl stop cockpit.socket cockpit.service 2>/dev/null || true
    systemctl disable cockpit.socket cockpit.service 2>/dev/null || true
    if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld 2>/dev/null; then
        firewall-cmd --permanent --remove-service=cockpit >/dev/null 2>&1 || true
        firewall-cmd --reload >/dev/null 2>&1 || true
    fi
fi
# === END: [2026-10-28] Отключение службы Cockpit на RHEL/AlmaLinux/CentOS ===

# 1. Проверка и генерация .env файла при его отсутствии
if [ ! -f ".env" ]; then
    echo "⚙️  Файл .env не найден. Запуск генерации параметров..."
    bash generate_env.sh "$DOMAIN_ARG"
fi

echo "Setting system timezone to Asia/Yekaterinburg..."
timedatectl set-timezone Asia/Yekaterinburg 2>/dev/null || echo "Failed to set timezone. Ignoring."

echo "Installing Docker if not present..."
if ! docker compose version >/dev/null 2>&1; then
    if command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
        echo "Configuring Docker CE repository for RHEL/AlmaLinux/CentOS/Rocky..."
        rpm --import https://download.docker.com/linux/centos/gpg 2>/dev/null || true
        curl -fsSL https://download.docker.com/linux/centos/docker-ce.repo -o /etc/yum.repos.d/docker-ce.repo
        if command -v dnf >/dev/null 2>&1; then
            dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        else
            yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        fi
        systemctl enable --now docker 2>/dev/null || true
    else
        curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh && rm -f get-docker.sh
        systemctl enable --now docker 2>/dev/null || true
    fi
fi

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
