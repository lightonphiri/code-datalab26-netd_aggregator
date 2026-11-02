#!/bin/bash
# After the 22.04 hop: PHP 8.1 from the ondrej PPA for jammy, packaged intl, no focal PHP left (November 2, 2026)
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
sed -i 's/^\(# \)\?deb .*ondrej.*$//' /etc/apt/sources.list.d/ondrej-ubuntu-php-focal.list 2>/dev/null || true
rm -f /etc/apt/sources.list.d/ondrej-ubuntu-php-focal.list*
add-apt-repository -y ppa:ondrej/php >/dev/null
# the hand-built intl of October 31, 2026 (docs/OPERATIONS.md) goes; the package replaces it
phpdismod -v 8.1 intl || true; rm -f /etc/php/8.1/mods-available/intl.ini /usr/lib/php/20210902/intl.so
apt-get update -q
P81=$(dpkg -l | awk '/^ii +php8\.1-/ {print $2}' | sed 's/:amd64//' | tr '\n' ' ')
echo "php8.1 packages: $P81"
apt-get install -y -q -o Dpkg::Options::=--force-confold $P81 php8.1-intl libapache2-mod-php8.1
apt-get purge -y -q $(dpkg -l | awk '/^(ii|rc) +(php7\.4|php8\.0|php8\.2|libapache2-mod-php7\.4|libapache2-mod-php8\.0|libapache2-mod-php8\.2)/ {print $2}') || true
apt-get -y -q autoremove
update-alternatives --set php /usr/bin/php8.1
a2enmod -q php8.1 >/dev/null; apache2ctl configtest && systemctl restart apache2
php -v | head -1; php -m | grep -ciE '^(intl|mysqli|pdo_mysql|gd|mbstring|xml|curl|zip)$'
echo PHP JAMMY DONE
