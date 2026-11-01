#!/bin/bash
# Run models, dry-run processing on a copy, and apply to the portal only if the dry run excludes at most
# MAX (default 10) records on a model's say (SRS FR-49, FR-52). Run as netd, e.g. via systemd-run (docs/OPERATIONS.md).
MAX=${MAX:-10}
set -e
cd /opt/netd/harvester
.venv/bin/python -m netd.cli predict
sqlite3 netd.sqlite3 ".backup /opt/netd/logs/dry.sqlite3"
.venv/bin/python -m netd.cli process --db /opt/netd/logs/dry.sqlite3
N=$(sqlite3 /opt/netd/logs/dry.sqlite3 "select count(*) from excluded where reason like '%model:%'")
echo "dry run: $N records excluded by a model"
if [ "$N" -gt "$MAX" ]; then echo "STOP: more model exclusions than expected; not applied"; exit 1; fi
flock -w 7200 run.lock .venv/bin/python -m netd.cli reprocess
echo APPLIED
