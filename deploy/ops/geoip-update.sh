#!/bin/bash
# Monthly refresh of the offline place database for the usage counts (SRS FR-61): DB-IP "IP to City Lite"
# (CC BY 4.0, https://db-ip.com). Tries this month's file, then last month's (published early each month). The
# portal reopens the file by itself within an hour. Run as netd; a failure keeps the previous file.
set -euo pipefail
D=/opt/netd/geoip
mkdir -p $D && cd $D
for m in $(date -u +%Y-%m) $(date -u -d '-1 month' +%Y-%m); do
  [ -f city.mmdb ] && [ "$(cat edition 2>/dev/null)" = "$m" ] && { echo "geoip: $m already installed"; exit 0; }
  if curl -sSf -m 600 -o city.mmdb.gz.new "https://download.db-ip.com/free/dbip-city-lite-$m.mmdb.gz"; then
    gunzip -c city.mmdb.gz.new > city.mmdb.new && rm -f city.mmdb.gz.new
    [ "$(stat -c %s city.mmdb.new)" -gt 50000000 ] || { echo "geoip: $m file too small"; rm -f city.mmdb.new; exit 1; }
    mv city.mmdb.new city.mmdb && echo "$m" > edition && echo "geoip: installed $m"; exit 0
  fi
done
echo "geoip: no edition found; keeping the previous file"; rm -f city.mmdb.gz.new
