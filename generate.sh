#!/bin/bash
cd /Users/uragan/gemini/sni-proxy-deploy
mkdir -p lists
curl -sL https://raw.githubusercontent.com/ImMALWARE/dns.malw.link/master/lists/domains.txt > lists/domains.txt
curl -sL https://raw.githubusercontent.com/ImMALWARE/dns.malw.link/master/lists/domains_with_subdomains.txt > lists/domains_with_subdomains.txt
touch lists/banned_ips.txt
curl -sL https://raw.githubusercontent.com/Internet-Helper/GeoHideDNS/main/hosts/hosts > geohide.tmp
awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ && $1 != "0.0.0.0" {print $2}' geohide.tmp | sort -u > all_geohide.tmp
awk 'NR==FNR{seen[$1]=1; next} !seen[$1]' lists/domains.txt all_geohide.tmp > lists/custom.txt
curl -sL https://raw.githubusercontent.com/ImMALWARE/dns.malw.link/master/hosts > malw.tmp
awk '$2 ~ /^(localhost|ip6-localhost|ip6-loopback|ip6-allnodes|ip6-allrouters|broadcasthost|local)$/ { next } /^::1/ { next } /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ && $1 != "0.0.0.0" { domain=$2; if (!seen_domain[domain]) { seen_domain[domain]=1; print "YOUR_VPS_IP " domain } next } { print $0 }' malw.tmp geohide.tmp > mega_hosts_template.txt
for gh_domain in "raw.githubusercontent.com" "release-assets.githubusercontent.com" "private-user-images.githubusercontent.com" "gist.githubusercontent.com" "avatars.githubusercontent.com"; do
  echo "$gh_domain" >> lists/custom.txt
  echo "YOUR_VPS_IP $gh_domain" >> mega_hosts_template.txt
done
rm *.tmp
git add .
git commit -m "fix: Add GitHub domains and remove localhost bugs"
GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new" git push
