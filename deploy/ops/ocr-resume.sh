#!/bin/bash
# Resume the OCR backlog when rims.unza.ac.zm answers; wait while it is down (session 04, November 1, 2026;
# moved into the repository in session 05, November 2, 2026). Run as a transient unit:
#   sudo systemd-run --unit=netd-mltext --uid=netd --gid=netd --working-directory=/opt/netd/harvester --nice=10 /bin/bash /opt/netd/deploy/ops/ocr-resume.sh
cd /opt/netd/harvester
end=$(( $(date +%s) + 24*3600 ))
left() { .venv/bin/python -m netd.cli text-report 2>/dev/null | awk '$1=="unza" && $2=="no_text" {print $3}'; }
while [ "$(date +%s)" -lt "$end" ]; do
  n=$(left); [ -z "$n" ] && n=0
  [ "$n" -eq 0 ] && break
  if curl -s -m 30 -o /dev/null -w '%{http_code}' 'https://rims.unza.ac.zm/server/oai/request?verb=Identify' | grep -q 200; then
    echo "repository up; $n PDFs left"
    flock -w 7200 run.lock .venv/bin/python -m netd.cli ocr-text --limit 50 || echo "batch failed"
  else
    echo "repository down; $n PDFs left; waiting 10 minutes"; sleep 600
  fi
done
echo "OCR backlog loop finished; $(left) PDFs left"
if curl -s -m 30 -o /dev/null https://rims.unza.ac.zm/; then
  flock -w 7200 run.lock .venv/bin/python -m netd.cli extract-text --retry-failed
fi
