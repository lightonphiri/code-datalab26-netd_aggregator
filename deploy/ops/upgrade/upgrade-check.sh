#!/bin/bash
# Service checks after each Ubuntu upgrade hop (session 05, November 2, 2026).
# Writes /var/backups/upgrade-checks/<release>-<time>.txt and prints it.
mkdir -p /var/backups/upgrade-checks
OUT=/var/backups/upgrade-checks/$(lsb_release -cs)-$(date -u +%Y%m%dT%H%M).txt
{
echo "== $(lsb_release -ds), kernel $(uname -r), $(date -u)"
for s in ssh apache2 mysql nginx tomcat orthanc-build netd-solr netd-portal; do printf '%-14s %s\n' "$s" "$(systemctl is-active $s)"; done
systemctl --failed --no-legend --no-pager | sed 's/^/failed unit: /'
echo "-- HTTP"
while read -r want url; do
  got=$(curl -s -m 60 -o /dev/null -w '%{http_code}' "$url"); [ "$got" = "$want" ] && r=OK || r="DIFF (want $want)"
  printf '%-4s %-12s %s\n' "$got" "$r" "$url"
done <<'EOF'
200 https://netd.ac.zm/
200 https://netd.ac.zm/catalog?q=malaria
200 https://netd.ac.zm/oai?verb=Identify
200 https://netd.ac.zm/api/v1/records?q=water
200 https://netd.ac.zm/quality
200 https://emi.org.zm/
200 https://emi.org.zm/user/login
200 https://etd2024.unza.zm/
200 https://netd.ac.zm/znrp/
302 https://netd.ac.zm/ojs/
401 http://127.0.0.1:8042/
302 http://127.0.0.1:8080/openmrs
200 http://127.0.0.1:8888/
200 http://127.0.0.1:8983/solr/netd/admin/ping
EOF
echo "-- versions"
php -v 2>/dev/null | head -1; apache2ctl -M 2>/dev/null | grep -i php; mysql --version
java -version 2>&1 | head -1; /usr/lib/jvm/java-8-openjdk-amd64/bin/java -version 2>&1 | head -1
/opt/netd/ruby/bin/ruby -v; cd /var/www/drupal_emiproject && sudo -u www-data vendor/bin/drush status --field=drupal-version 2>&1 | head -1
echo "-- NETD"
cd /opt/netd/harvester && sudo -u netd .venv/bin/python -m netd.cli check 2>&1 | tail -3
echo "-- compat libraries still needed (not found without the shim)"
for b in /home/emiproject/work_package-2/pacs-orthanc/orthanc/Build/Orthanc /opt/netd/ruby/lib/ruby/3.3.0/x86_64-linux/openssl.so; do
  printf '%s: %s\n' "$(basename $b)" "$(ldd $b 2>/dev/null | grep -c 'not found') missing"; done
} 2>&1 | tee "$OUT"
