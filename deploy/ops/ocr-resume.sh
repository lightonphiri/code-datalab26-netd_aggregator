#!/bin/bash
# Resume the OCR backlog when rims.unza.ac.zm answers; wait while it is down (session 04, November 1, 2026;
# moved into the repository in session 05; session 06, November 2, 2026: window set by WINDOW_HOURS, and when the
# backlog is done it retries failed fetches, runs the guarded apply and writes the held-out evaluation, by kind
# of PDF text, to /opt/netd/logs/eval-final-{test,dev}.txt). Run as a transient unit:
#   sudo systemd-run --unit=netd-mltext --uid=netd --gid=netd --working-directory=/opt/netd/harvester --nice=10 \
#     --setenv=WINDOW_HOURS=168 /bin/bash /opt/netd/deploy/ops/ocr-resume.sh
cd /opt/netd/harvester
end=$(( $(date +%s) + ${WINDOW_HOURS:-24}*3600 ))
left() { .venv/bin/python -m netd.cli text-report 2>/dev/null | awk '$1=="unza" && $2=="no_text" {print $3}'; }
up() { curl -s -m 30 -o /dev/null -w '%{http_code}' 'https://rims.unza.ac.zm/server/oai/request?verb=Identify' | grep -q 200; }
while [ "$(date +%s)" -lt "$end" ]; do
  n=$(left); [ -z "$n" ] && n=0
  [ "$n" -eq 0 ] && break
  if up; then
    echo "repository up; $n PDFs left"
    flock -w 7200 run.lock .venv/bin/python -m netd.cli ocr-text --limit 50 || echo "batch failed"
  else
    echo "repository down; $n PDFs left; waiting 10 minutes"; sleep 600
  fi
done
n=$(left); echo "OCR backlog loop finished; ${n:-0} PDFs left"
[ "${n:-0}" -eq 0 ] || exit 0
if up; then
  flock -w 7200 run.lock .venv/bin/python -m netd.cli extract-text --retry-failed
  flock -w 7200 run.lock .venv/bin/python -m netd.cli ocr-text || true   # PDFs the retry found to be scanned
fi
.venv/bin/python -m netd.cli text-report > /opt/netd/logs/text-report-final.txt
/bin/bash /opt/netd/deploy/ops/netd-ml-apply.sh || echo "apply stopped by its guard: check journalctl"
for h in test dev; do
  .venv/bin/python -m netd.cli evaluate /opt/netd/logs/gold-unza-2020-$h.csv --strata > /opt/netd/logs/eval-final-$h.txt
done
echo "final evaluation written to /opt/netd/logs/eval-final-test.txt and eval-final-dev.txt"
