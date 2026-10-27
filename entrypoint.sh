#!/bin/sh

# Копируем наш конфиг Nginx
cp /etc/nginx/nginx.conf.template /etc/nginx/nginx.conf

# Создание конфигураций whitelist на основе списков
echo "" > /etc/nginx/whitelist_domains.conf
echo "" > /etc/nginx/banned_ips.conf

# Обработка domains.txt с использованием awk для регулярных выражений
if [ -f /etc/nginx/lists/domains.txt ]; then
    awk 'NF {
        # Экранируем точки для regex
        gsub(/\./, "\\\\.");
        print "~(^|\\\\.)" $0 "$ 1;"
    }' /etc/nginx/lists/domains.txt > /etc/nginx/whitelist_domains.conf
fi

# Обработка banned_ips.txt
if [ -f /etc/nginx/lists/banned_ips.txt ]; then
    awk 'NF {print $0 " 1;"}' /etc/nginx/lists/banned_ips.txt > /etc/nginx/banned_ips.conf
fi

# === START: [2026-10-28] Автоматическое обнаружение SSL-сертификатов и подготовка ACME ===
mkdir -p /etc/nginx/ssl_active
mkdir -p /var/www/certbot

CERT_FOUND=0
if [ -d /etc/nginx/certs ]; then
    CERT_FILE=$(find /etc/nginx/certs -type f \( -name "fullchain.pem" -o -name "fullchain.cer" \) -exec ls -1t {} + 2>/dev/null | head -n 1)
    if [ -n "$CERT_FILE" ]; then
        CERT_DIR=$(dirname "$CERT_FILE")
        KEY_FILE=$(find "$CERT_DIR" -type f \( -name "privkey.pem" -o -name "*.key" \) 2>/dev/null | head -n 1)
        if [ -n "$KEY_FILE" ]; then
            ln -sf "$CERT_FILE" /etc/nginx/ssl_active/fullchain.pem
            ln -sf "$KEY_FILE" /etc/nginx/ssl_active/privkey.pem
            CERT_FOUND=1
        fi
    fi
fi

if [ "$CERT_FOUND" -eq 0 ] && [ ! -f /etc/nginx/ssl_active/fullchain.pem ]; then
    # Резервный самоподписанный сертификат для первичного старта
    if ! command -v openssl >/dev/null 2>&1; then
        echo "[*] Installing openssl in container for fallback certificate..."
        apk add --no-cache openssl >/dev/null 2>&1 || true
    fi
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl_active/privkey.pem \
        -out /etc/nginx/ssl_active/fullchain.pem \
        -subj "/CN=localhost" 2>/dev/null || true
fi

# Настройка пути веб-панели 3X-UI из переменной окружения
XUI_PATH="${XUI_PATH:-/xui/}"
case "$XUI_PATH" in
    /*) ;;
    *) XUI_PATH="/$XUI_PATH" ;;
esac
case "$XUI_PATH" in
    */) ;;
    *) XUI_PATH="$XUI_PATH/" ;;
esac
sed -i "s|__XUI_BASE_PATH__|$XUI_PATH|g" /etc/nginx/nginx.conf

# === START: [2026-10-28] Подстановка секретного пути подписки 3X-UI ===
# Настройка пути подписки 3X-UI из переменной окружения
SUB_PATH="${SUB_PATH:-/sub/}"
case "$SUB_PATH" in
    /*) ;;
    *) SUB_PATH="/$SUB_PATH" ;;
esac
case "$SUB_PATH" in
    */) ;;
    *) SUB_PATH="$SUB_PATH/" ;;
esac
sed -i "s|__SUB_BASE_PATH__|$SUB_PATH|g" /etc/nginx/nginx.conf
# === END: [2026-10-28] Подстановка секретного пути подписки 3X-UI ===

# Настройка Reality SNI из переменной окружения
REALITY_SNI="${REALITY_SNI:-www.nvidia.com}"
sed -i "s|__REALITY_SNI__|$REALITY_SNI|g" /etc/nginx/nginx.conf
# === END: [2026-10-28] Автоматическое обнаружение SSL-сертификатов и подготовка ACME ===

# Запуск Nginx
exec nginx -g "daemon off;"
