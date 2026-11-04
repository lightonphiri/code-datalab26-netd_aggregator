#!/bin/bash
# Every 15 minutes: is the portal (NETD_BASE_URL in deploy/site.env) serving search results? Alerts once per outage, and once on recovery.
S=/var/lib/netd-probe.down
. /opt/netd/deploy/site.env   # NETD_BASE_URL, written by deploy.sh from config/country.yml
ok() { curl -sf --max-time 30 "$NETD_BASE_URL/catalog?q=education&per_page=1" | grep -q 'class="documentHeader'; }
if ok || { sleep 60; ok; }; then
  [ -f $S ] && { SINCE=$(cat $S 2>/dev/null); rm -f $S; /usr/bin/python3 /opt/netd/deploy/ops/netd-alert.py --recovered "down since $SINCE"; }
  exit 0
fi
[ -f $S ] && exit 0            # already alerted for this outage
date -Is > $S
echo "$NETD_BASE_URL/ is not serving search results (two attempts, 60 s apart)"; exit 1
