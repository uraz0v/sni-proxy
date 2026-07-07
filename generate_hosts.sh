#!/bin/bash

# Скрипт выполняется на вашем локальном компьютере для генерации hosts файла для роутера
if [ -z "$1" ]; then
  echo "Использование: $0 <IP_вашего_VPS>"
  exit 1
fi

SERVER_IP="$1"
OUTPUT_FILE="mega_hosts.txt"

if [ ! -f "mega_hosts_template.txt" ]; then
  echo "Ошибка: шаблон mega_hosts_template.txt не найден! Выполните git pull или подождите, пока отработает GitHub Actions."
  exit 1
fi

echo "Подставляем IP $SERVER_IP в шаблон..."
sed "s/YOUR_VPS_IP/$SERVER_IP/g" mega_hosts_template.txt > "$OUTPUT_FILE"

echo "✅ Файл $OUTPUT_FILE успешно обновлен!"
echo "Команда для отправки на роутер (OpenWrt):"
echo "ssh root@РОУТЕР_IP 'head -n 5 /etc/hosts > /tmp/hosts.tmp && mv /tmp/hosts.tmp /etc/hosts && tee -a /etc/hosts >/dev/null && /etc/init.d/dnsmasq restart' < $OUTPUT_FILE"
