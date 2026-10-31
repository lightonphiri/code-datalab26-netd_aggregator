#!/bin/bash
# Every 15 minutes: is https://netd.ac.zm/ serving search results? Alerts once per outage, and once on recovery.
S=/var/lib/netd-probe.down
ok() { curl -sf --max-time 30 "https://netd.ac.zm/catalog?q=education&per_page=1" | grep -q 'class="documentHeader'; }
if ok || { sleep 60; ok; }; then
  [ -f $S ] && { rm -f $S; /usr/bin/python3 /opt/netd/deploy/ops/netd-alert.py --recovered "down since $(cat $S 2>/dev/null)"; }
  exit 0
fi
[ -f $S ] && exit 0            # already alerted for this outage
date -Is > $S
echo "https://netd.ac.zm/ is not serving search results (two attempts, 60 s apart)"; exit 1
