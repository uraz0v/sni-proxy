#!/bin/sh

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

# Запуск Nginx
exec nginx -g "daemon off;"
