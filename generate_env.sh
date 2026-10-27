#!/bin/bash

# # === START: [2026-10-28] Генерация параметров и создание файла .env ===
set -e

ENV_FILE=".env"
FORCE=false
INPUT_DOMAIN=""

for arg in "$@"; do
    case "$arg" in
        --force|-f)
            FORCE=true
            ;;
        *)
            if [ -z "$INPUT_DOMAIN" ]; then
                INPUT_DOMAIN="$arg"
            fi
            ;;
    esac
done

if [ -f "$ENV_FILE" ] && [ "$FORCE" = false ]; then
    echo "⚠️  Файл $ENV_FILE уже существует."
    if [ -t 0 ]; then
        read -rp "Перезаписать файл $ENV_FILE новыми случайными параметрами? [y/N]: " CONFIRM
        case "$CONFIRM" in
            [yY][eE][sS]|[yY])
                echo "Перезапись файла $ENV_FILE..."
                ;;
            *)
                echo "Сохраняем существующий $ENV_FILE без изменений."
                exit 0
                ;;
        esac
    else
        echo "Пропуск генерации: $ENV_FILE сохранен."
        exit 0
    fi
fi

echo "=========================================================="
echo "      Генерация параметров окружения для SNI Proxy        "
echo "=========================================================="

# 1. Домен сервера
SERVER_DOMAIN="$INPUT_DOMAIN"
if [ -z "$SERVER_DOMAIN" ]; then
    if [ -t 0 ]; then
        read -rp "Введите домен сервера (например, vps.example.com): " SERVER_DOMAIN
    fi
fi

if [ -z "$SERVER_DOMAIN" ]; then
    # Попытка определить домен через hostname или внешний IP
    AUTO_HOSTNAME=$(hostname -f 2>/dev/null || hostname 2>/dev/null || true)
    if echo "$AUTO_HOSTNAME" | grep -q "\."; then
        SERVER_DOMAIN="$AUTO_HOSTNAME"
    else
        SERVER_DOMAIN=$(curl -s4 --connect-timeout 3 https://ifconfig.me 2>/dev/null || echo "127.0.0.1")
    fi
fi

echo "✓ Домен сервера: $SERVER_DOMAIN"

# 2. Секретный путь для веб-панели 3X-UI (16 символов)
RAND_PATH=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom 2>/dev/null | head -c 16 || openssl rand -hex 8)
XUI_PATH="/${RAND_PATH}/"
echo "✓ Секретный путь панели: $XUI_PATH"

# === START: [2026-10-28] Генерация секретного пути для подписки 3X-UI ===
# Секретный путь для сервиса подписок 3X-UI (12 символов, скрыт от зондов ТСПУ)
RAND_SUB=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom 2>/dev/null | head -c 12 || openssl rand -hex 6)
SUB_PATH="/s_${RAND_SUB}/"
echo "✓ Секретный путь подписки: $SUB_PATH"
# === END: [2026-10-28] Генерация секретного пути для подписки 3X-UI ===

# 3. Домен маскировки для Reality
REALITY_SNI="www.nvidia.com"
echo "✓ Маскировочный SNI Reality: $REALITY_SNI"

# 4. Email для ACME / Let's Encrypt
if echo "$SERVER_DOMAIN" | grep -q "\."; then
    ACME_EMAIL="admin@${SERVER_DOMAIN}"
else
    ACME_EMAIL="admin@example.com"
fi
echo "✓ Email для Let's Encrypt: $ACME_EMAIL"

# 5. Логин и пароль администратора 3X-UI
XUI_USER="admin"
XUI_PASSWORD=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom 2>/dev/null | head -c 14 || openssl rand -hex 7)
echo "✓ Логин 3X-UI: $XUI_USER"
echo "✓ Пароль 3X-UI: $XUI_PASSWORD"

# Запись в .env
cat > "$ENV_FILE" <<EOF
# ====================================================================
# Параметры развертывания SNI Proxy & 3X-UI
# Сгенерировано: $(date '+%Y-%m-%d %H:%M:%S')
# ====================================================================

# Домен сервера (для Let's Encrypt, маскировки и клиентов)
SERVER_DOMAIN=${SERVER_DOMAIN}

# Секретный путь для входа в панель 3X-UI через порт 443
XUI_PATH=${XUI_PATH}

# === START: [2026-10-28] Секретный путь для сервиса подписок ===
# Секретный путь для сервиса подписок 3X-UI (скрыт от активного зондирования ТСПУ)
SUB_PATH=${SUB_PATH}
# === END: [2026-10-28] Секретный путь для сервиса подписок ===

# Маскировочный домен для Xray Reality
REALITY_SNI=${REALITY_SNI}

# Email для регистрации и уведомлений Let's Encrypt
ACME_EMAIL=${ACME_EMAIL}

# Учетные данные администратора панели 3X-UI
XUI_USER=${XUI_USER}
XUI_PASSWORD=${XUI_PASSWORD}
EOF

chmod 600 "$ENV_FILE"

echo "=========================================================="
echo "✅ Конфигурация успешно сохранена в $ENV_FILE"
echo "   Путь панели:   https://${SERVER_DOMAIN}${XUI_PATH}"
echo "   Путь подписки: https://${SERVER_DOMAIN}${SUB_PATH}<subId>"
echo "   Логин:         ${XUI_USER}"
echo "   Пароль:        ${XUI_PASSWORD}"
echo "=========================================================="
# # === END: [2026-10-28] Генерация параметров и создание файла .env ===
