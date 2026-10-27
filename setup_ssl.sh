#!/bin/bash

# # === START: [2026-10-28] Автоматическая установка acme.sh и выпуск сертификата Let's Encrypt ===
set -e

ENV_FILE=".env"
if [ -f "$ENV_FILE" ]; then
    # Загружаем переменные без экспорта
    SERVER_DOMAIN=$(grep -E '^SERVER_DOMAIN=' "$ENV_FILE" | cut -d'=' -f2- | tr -d '\r"' || true)
    ACME_EMAIL=$(grep -E '^ACME_EMAIL=' "$ENV_FILE" | cut -d'=' -f2- | tr -d '\r"' || true)
fi

SERVER_DOMAIN="${SERVER_DOMAIN:-$1}"
ACME_EMAIL="${ACME_EMAIL:-admin@$SERVER_DOMAIN}"

if [ -z "$SERVER_DOMAIN" ]; then
    echo "⚠️  Домен сервера не указан. Пропуск настройки Let's Encrypt."
    exit 0
fi

# Проверка, является ли домен IP-адресом
if echo "$SERVER_DOMAIN" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$|^127\.'; then
    echo "ℹ️  Указан IP-адрес ($SERVER_DOMAIN). Let's Encrypt требует доменное имя."
    echo "   Nginx будет использовать встроенный самоподписанный SSL-сертификат."
    exit 0
fi

CERT_DIR="/root/cert/$SERVER_DOMAIN"
FULLCHAIN="$CERT_DIR/fullchain.pem"
PRIVKEY="$CERT_DIR/privkey.pem"

# Проверка существующего сертификата
if [ -f "$FULLCHAIN" ] && [ -f "$PRIVKEY" ]; then
    if openssl x509 -checkend 86400 -noout -in "$FULLCHAIN" 2>/dev/null; then
        echo "✅ Сертификат для $SERVER_DOMAIN уже существует и действителен."
        exit 0
    else
        echo "🔄 Срок действия сертификата для $SERVER_DOMAIN истекает, запускаем обновление..."
    fi
fi

echo "=========================================================="
echo "    Настройка SSL Let's Encrypt через acme.sh для $SERVER_DOMAIN "
echo "=========================================================="

# 1. Поиск или установка acme.sh
ACME_BIN=""
if [ -f "$HOME/.acme.sh/acme.sh" ]; then
    ACME_BIN="$HOME/.acme.sh/acme.sh"
elif [ -f "/root/.acme.sh/acme.sh" ]; then
    ACME_BIN="/root/.acme.sh/acme.sh"
elif command -v acme.sh >/dev/null 2>&1; then
    ACME_BIN=$(command -v acme.sh)
fi

if [ -z "$ACME_BIN" ]; then
    echo "📦 acme.sh не найден в системе. Выполняем установку..."
    # Установка зависимостей (socat / curl)
    if command -v dnf >/dev/null 2>&1; then
        dnf install -y socat curl openssl cronie 2>/dev/null || true
        systemctl enable --now crond 2>/dev/null || true
    elif command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq && apt-get install -y -qq socat curl openssl cron 2>/dev/null || true
        systemctl enable --now cron 2>/dev/null || true
    fi

    curl -sL https://get.acme.sh | sh -s email="$ACME_EMAIL"
    ACME_BIN="$HOME/.acme.sh/acme.sh"
    if [ ! -f "$ACME_BIN" ]; then
        ACME_BIN="/root/.acme.sh/acme.sh"
    fi
fi

if [ ! -f "$ACME_BIN" ]; then
    echo "❌ Ошибка: не удалось установить acme.sh."
    exit 1
fi

echo "✓ acme.sh готов: $ACME_BIN"
"$ACME_BIN" --set-default-ca --server letsencrypt >/dev/null 2>&1 || true

# 2. Подготовка каталогов и fallback SSL
mkdir -p /var/www/certbot
mkdir -p "$CERT_DIR"
mkdir -p /root/cert/fallback

# Если в /root/cert нет ни одного сертификата, создаем временный на хосте
if [ -z "$(find /root/cert -type f -name 'fullchain.pem' 2>/dev/null)" ]; then
    echo "📄 Создание временного SSL-сертификата для первичного запуска Nginx..."
    openssl req -x509 -nodes -days 1 -newkey rsa:2048 \
        -keyout /root/cert/fallback/privkey.pem \
        -out /root/cert/fallback/fullchain.pem \
        -subj "/CN=temporary" 2>/dev/null || true
fi

# 3. Обеспечение работы Nginx на 80 порту для ACME-челленджа
echo "🌐 Запуск контейнера Nginx для прохождения проверки домена..."
docker compose up -d sni-proxy

# 4. Выпуск сертификата через Webroot
echo "🔒 Выпуск SSL-сертификата для $SERVER_DOMAIN..."
"$ACME_BIN" --issue -d "$SERVER_DOMAIN" -w /var/www/certbot --force || {
    echo "⚠️  Первая попытка выпуска не удалась. Повторяем с флагом --server letsencrypt..."
    "$ACME_BIN" --issue -d "$SERVER_DOMAIN" -w /var/www/certbot --server letsencrypt --force
}

# 5. Установка сертификата в /root/cert/<domain>/
echo "📂 Установка сертификата в $CERT_DIR..."
"$ACME_BIN" --install-cert -d "$SERVER_DOMAIN" \
    --fullchain-file "$FULLCHAIN" \
    --key-file "$PRIVKEY" \
    --reloadcmd "docker compose exec -T sni-proxy nginx -s reload 2>/dev/null || true"

# 6. Перезапуск Nginx для монтирования боевого сертификата
docker compose restart sni-proxy

echo "=========================================================="
echo "✅ Сертификат Let's Encrypt успешно выпущен и активирован!"
echo "   Путь: $FULLCHAIN"
echo "=========================================================="
# # === END: [2026-10-28] Автоматическая установка acme.sh и выпуск сертификата Let's Encrypt ===
