#!/bin/bash
# Nightly NETD backup (run as root by netd-backup.service, after the daily harvest).
# Writes /var/backups/netd/YYYY-MM-DD/ only if every step succeeds; keeps 14 days on the server.
#   netd.sqlite3.gz       staging store (raw OAI-PMH XML + canonical records): the system of record
#   portal.sqlite3.gz     portal database (problem reports, admin accounts, admin activity log)
#   csv-sources.tgz       CSV files received from institutions (harvester/uploads/) and sources.local.yml
#   solr-conf.tgz         Solr configset in use
#   MANIFEST.txt          record counts per source, Solr count, versions
#   SHA256SUMS            checksums of the above
# The Solr index itself is not copied: it is rebuilt from the staging store (see docs/OPERATIONS.md).
# portal.env (secrets) is deliberately NOT backed up.
set -Eeuo pipefail
N=/opt/netd; B=/var/backups/netd; D=$(date +%F); LOG=/var/log/netd-backup.log
mkdir -p "$B"; chmod 700 "$B"
T=$(mktemp -d "$B/.tmp-$D-XXXX")
trap 'echo "$(date -Is) backup FAILED (line $LINENO)" >>$LOG; rm -rf "$T"; exit 1' ERR

# read the store as netd: it is in WAL mode, and root must not leave root-owned -wal/-shm files behind
runuser -u netd -- sqlite3 "$N/harvester/netd.sqlite3" ".backup '$N/logs/.netd-backup.sqlite3'"
mv "$N/logs/.netd-backup.sqlite3" "$T/netd.sqlite3"
[ "$(sqlite3 "$T/netd.sqlite3" 'PRAGMA integrity_check')" = ok ]
sqlite3 "$N/portal/storage/production.sqlite3" ".backup '$T/portal.sqlite3'"
[ "$(sqlite3 "$T/portal.sqlite3" 'PRAGMA integrity_check')" = ok ]
tar -czf "$T/solr-conf.tgz" -C "$N/solr-home/netd" conf core.properties
tar -czf "$T/csv-sources.tgz" -C "$N/harvester" uploads $( [ -f "$N/harvester/sources.local.yml" ] && echo sources.local.yml )

# After a reboot the missed run starts before Solr is ready: wait up to 3 minutes (November 2, 2026)
for i in $(seq 1 36); do curl -sf -o /dev/null 'http://127.0.0.1:8983/solr/netd/admin/ping' && break; sleep 5; done
SOLR=$(curl -sf 'http://127.0.0.1:8983/solr/netd/select?q=*:*&rows=0&wt=json' | python3 -c 'import json,sys;print(json.load(sys.stdin)["response"]["numFound"])')
{
  echo "NETD backup $D (taken $(date -Is) on $(hostname))"
  echo "Solr documents: $SOLR"
  echo "Staging records per source:"
  sqlite3 "$T/netd.sqlite3" "SELECT '  '||source||' '||count(*) FROM records GROUP BY source"
  echo "Problem reports: $(sqlite3 "$T/portal.sqlite3" 'SELECT count(*) FROM problem_reports' 2>/dev/null || echo n/a)"
  echo "Code deployed: $(cat $N/deploy/VERSION 2>/dev/null || echo unknown)"
} > "$T/MANIFEST.txt"
gzip -9 "$T/netd.sqlite3" "$T/portal.sqlite3"
(cd "$T" && sha256sum netd.sqlite3.gz portal.sqlite3.gz solr-conf.tgz csv-sources.tgz MANIFEST.txt > SHA256SUMS && sha256sum -c --quiet SHA256SUMS)

rm -rf "$B/$D"; mv "$T" "$B/$D"; ln -sfn "$B/$D" "$B/latest"
find "$B" -maxdepth 1 -type d -name '20??-??-??' -mtime +14 -exec rm -rf {} +
echo "$(date -Is) backup OK $B/$D ($(du -sh "$B/$D" | cut -f1), $SOLR docs)" >>$LOG
