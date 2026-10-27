#!/bin/bash

# === START: [2026-10-28] Единый онлайн-установщик комплекса SNI-прокси и 3X-UI ===
set -e

REPO_URL="https://github.com/uraz0v/sni-proxy.git"
INSTALL_DIR="/opt/sni-proxy"
DOMAIN="$1"

echo "=========================================================="
echo "    Установка SNI Proxy & 3X-UI (github.com/uraz0v)       "
echo "=========================================================="

# 1. Проверка и автоматическая установка git и базовых зависимостей
if ! command -v git >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
    echo "📦 Установка git и curl в систему..."
    if command -v dnf >/dev/null 2>&1; then
        dnf install -y git curl
    elif command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq && apt-get install -y -qq git curl
    elif command -v yum >/dev/null 2>&1; then
        yum install -y git curl
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache git curl
    else
        echo "❌ Не удалось определить пакетный менеджер. Установите git вручную."
        exit 1
    fi
fi

# 2. Клонирование или обновление репозитория
if [ -d "$INSTALL_DIR/.git" ]; then
    echo "🔄 Обновление репозитория в $INSTALL_DIR..."
    cd "$INSTALL_DIR"
    git pull origin main
else
    echo "📥 Клонирование репозитория в $INSTALL_DIR..."
    mkdir -p "$(dirname "$INSTALL_DIR")"
    git clone "$REPO_URL" "$INSTALL_DIR"
    cd "$INSTALL_DIR"
fi

# 3. Выдача прав на выполнение
chmod +x deploy.sh generate_env.sh setup_ssl.sh update_lists.sh

# 4. Запуск основного сценария деплоя
./deploy.sh "$DOMAIN"
# === END: [2026-10-28] Единый онлайн-установщик комплекса SNI-прокси и 3X-UI ===
