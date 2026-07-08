#!/bin/bash
cd "$(dirname "$0")" || exit

# В этой переменной через запятую перечислите нужные сервисы из GeoHideDNS
SERVICES_TO_PROXY="ChatGPT (OpenAI),Claude,Google AI,GitHub Copilot,Canva,Notion,Docker,Spotify"

mkdir -p lists
# Очищаем старые списки, так как теперь мы всё контролируем сами
echo "" > lists/domains.txt
echo "" > lists/domains_with_subdomains.txt
touch lists/banned_ips.txt

# 1. Качаем файл GeoHideDNS
curl -sL https://raw.githubusercontent.com/Internet-Helper/GeoHideDNS/main/hosts/hosts > geohide.tmp

# 2. Вырезаем только нужные сервисы с помощью умного awk
awk -v wanted="$SERVICES_TO_PROXY" '
BEGIN {
    split(wanted, w, ",");
    for (i in w) { targets["# " w[i]] = 1 }
}
/^# / { extract = ($0 in targets) ? 1 : 0 }
extract && /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ && $1 != "0.0.0.0" { print $2 }
' geohide.tmp | sort -u > filtered_services.tmp

# 3. Сохраняем эти домены для Nginx (в custom.txt)
cat filtered_services.tmp > lists/custom.txt

# 4. Качаем файл от dns.malw.link чисто ради блокировки рекламы (0.0.0.0)
curl -sL https://raw.githubusercontent.com/ImMALWARE/dns.malw.link/master/hosts > malw.tmp

# 5. Формируем шаблон для роутера
# Сначала забираем все 0.0.0.0 (рекламу) из malw
awk '/^0\.0\.0\.0/ {print $0}' malw.tmp > mega_hosts_template.txt

# Затем добавляем наши выбранные сервисы с IP-адресом VPS
awk '{print "YOUR_VPS_IP " $1}' filtered_services.tmp >> mega_hosts_template.txt

# 6. Добавляем системные домены для работы роутера и GitHub
for gh_domain in "raw.githubusercontent.com" "release-assets.githubusercontent.com" "private-user-images.githubusercontent.com" "gist.githubusercontent.com" "avatars.githubusercontent.com"; do
  echo "$gh_domain" >> lists/custom.txt
  echo "YOUR_VPS_IP $gh_domain" >> mega_hosts_template.txt
done

# Чистим временные файлы
rm *.tmp

