#!/bin/bash
# Run models, dry-run processing on a copy, and apply to the portal only if the dry run excludes at most
# MAX (default 10) records on a model's say that are not already excluded on the live store (SRS FR-49, FR-52).
# Exclusions already live were checked by hand when they were first applied, so only new ones count
# (session 06, November 2, 2026). Run as netd, e.g. via systemd-run (docs/OPERATIONS.md).
MAX=${MAX:-10}
set -e
cd /opt/netd/harvester
.venv/bin/python -m netd.cli predict
sqlite3 netd.sqlite3 ".backup /opt/netd/logs/dry.sqlite3"
.venv/bin/python -m netd.cli process --db /opt/netd/logs/dry.sqlite3
Q="attach 'file:/opt/netd/harvester/netd.sqlite3?mode=ro' as live;"
N=$(sqlite3 /opt/netd/logs/dry.sqlite3 "select count(*) from excluded where reason like '%model:%'")
NEW=$(sqlite3 /opt/netd/logs/dry.sqlite3 "$Q select count(*) from main.excluded where reason like '%model:%'
  and id not in (select id from live.excluded where reason like '%model:%')")
echo "dry run: $N records excluded by a model, $NEW of them new"
if [ "$NEW" -gt 0 ]; then
  sqlite3 -separator ' | ' /opt/netd/logs/dry.sqlite3 "$Q select id, title, reason from main.excluded
    where reason like '%model:%' and id not in (select id from live.excluded where reason like '%model:%')"
fi
if [ "$NEW" -gt "$MAX" ]; then echo "STOP: more new model exclusions than expected; not applied"; exit 1; fi
flock -w 7200 run.lock .venv/bin/python -m netd.cli reprocess
echo APPLIED
