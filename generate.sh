#!/bin/bash
cd "$(dirname "$0")" || exit

# Если вы хотите проксировать ВСЕ доступные геоблоки, напишите "ALL"
# Если хотите только конкретные, перечислите их через запятую (например: "ChatGPT (OpenAI),Claude,Spotify")
SERVICES_TO_PROXY="ALL"

mkdir -p lists
# Очищаем старые списки, так как теперь мы всё контролируем сами
echo "" > lists/domains.txt
echo "" > lists/domains_with_subdomains.txt
touch lists/banned_ips.txt

# 1. Качаем файл GeoHideDNS
curl -sL https://raw.githubusercontent.com/Internet-Helper/GeoHideDNS/main/hosts/hosts > geohide.tmp

# Генерируем шпаргалку для пользователя (список всех доступных сервисов)
awk '/^# / && !/(Последнее|Домены|http|[0-9]+\.[0-9]+|В итоговом|Работающие|Только эти|Остальное|Решение)/ {print substr($0, 3)}' geohide.tmp > lists/available_services.txt

if [ "$SERVICES_TO_PROXY" = "ALL" ]; then
    SERVICES_TO_PROXY=$(paste -sd "," lists/available_services.txt)
fi

# 2. Вырезаем только нужные сервисы с заголовками и без дубликатов
awk -v wanted="$SERVICES_TO_PROXY" '
BEGIN {
    split(wanted, w, ",");
    for (i in w) { targets["# " w[i]] = 1 }
}
/^# / { 
    if ($0 in targets) { 
        extract = 1
        print "\n" $0 
    } else { 
        extract = 0 
    }
}
extract && /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ && $1 != "0.0.0.0" { 
    domain = $2
    if (!seen[domain]) {
        seen[domain] = 1
        print domain
    }
}
' geohide.tmp > filtered_services_with_headers.tmp

# 3. Сохраняем эти домены для Nginx (в custom.txt), убирая пустые строки и комментарии
awk '!/^#/ && !/^$/ {print $0}' filtered_services_with_headers.tmp > lists/custom.txt

# 4. Качаем файл от dns.malw.link чисто ради блокировки рекламы (0.0.0.0)
curl -sL https://raw.githubusercontent.com/ImMALWARE/dns.malw.link/master/hosts > malw.tmp

# 5. Формируем шаблон для роутера
echo "# ==============================" > mega_hosts_template.txt
echo "# БЛОКИРОВКА РЕКЛАМЫ (dns.malw.link)" >> mega_hosts_template.txt
echo "# ==============================" >> mega_hosts_template.txt
awk '/^0\.0\.0\.0/ {print $0}' malw.tmp >> mega_hosts_template.txt

echo "" >> mega_hosts_template.txt
echo "# ==============================" >> mega_hosts_template.txt
echo "# ПРОКСИРОВАНИЕ СЕРВИСОВ (GeoHide)" >> mega_hosts_template.txt
echo "# ==============================" >> mega_hosts_template.txt

# Добавляем выбранные сервисы, сохраняя заголовки блоков
awk '{
  if (/^#/ || /^$/) { print $0 }
  else { print "YOUR_VPS_IP " $1 }
}' filtered_services_with_headers.tmp >> mega_hosts_template.txt


# 6. Добавляем системные домены для работы роутера и GitHub
for gh_domain in "raw.githubusercontent.com" "release-assets.githubusercontent.com" "private-user-images.githubusercontent.com" "gist.githubusercontent.com" "avatars.githubusercontent.com"; do
  echo "$gh_domain" >> lists/custom.txt
  echo "YOUR_VPS_IP $gh_domain" >> mega_hosts_template.txt
done

# Чистим временные файлы
rm *.tmp

