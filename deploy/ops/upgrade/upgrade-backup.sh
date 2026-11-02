#!/bin/bash
# Full server backup before the Ubuntu upgrade (session 05, November 2, 2026).
# Writes /var/backups/upgrade-<date>/, then copies it to Google Drive and verifies it.
set -Eeuo pipefail
D=$(date -u +%Y-%m-%d); B=/var/backups/upgrade-$D; mkdir -p "$B"; cd "$B"
log() { echo "$(date -u +%H:%M:%S) $*"; }
command -v zstd >/dev/null || apt-get install -y -q zstd >/dev/null
Z="zstd -T2 -3 -q"

log "package state"
lsb_release -ds > os-release.txt
dpkg --get-selections > dpkg-selections.txt; apt-mark showmanual > apt-manual.txt
mkdir -p apt-sources; cp -a /etc/apt/sources.list /etc/apt/sources.list.d apt-sources/
systemctl list-unit-files --no-pager > unit-files.txt
ldd /home/emiproject/work_package-2/pacs-orthanc/orthanc/Build/Orthanc > orthanc-ldd.txt || true

log "NETD SQLite stores (consistent copies, as netd)"
sudo -u netd sqlite3 /opt/netd/harvester/netd.sqlite3 ".backup /tmp/netd-store.sqlite3"
sudo -u netd sqlite3 /opt/netd/portal/storage/production.sqlite3 ".backup /tmp/netd-portal.sqlite3"
mv /tmp/netd-store.sqlite3 /tmp/netd-portal.sqlite3 "$B/"; $Z --rm netd-store.sqlite3 netd-portal.sqlite3

log "MySQL dump (all databases)"
mysqldump --all-databases --single-transaction --routines --events --triggers --set-gtid-purged=OFF | $Z > mysql-all.sql.zst

log "Orthanc (custom build) stopped for a consistent copy of its index and storage"
trap "systemctl start orthanc-build" EXIT; systemctl stop orthanc-build
log "archives"
# tar exits 1 when a file changes while read (logs, live Solr): acceptable here
T() { out=$1; shift; { tar -C / -cf - "$@" 2>/dev/null || [ $? -eq 1 ]; } | $Z > "$out"; }
T system.tar.zst etc root usr/local var/spool/cron var/lib/orthanc var/www
T opt.tar.zst opt
T home.tar.zst home
systemctl start orthanc-build
log "Orthanc started again: $(systemctl is-active orthanc-build)"

sha256sum * > SHA256SUMS 2>/dev/null || true
du -sh "$B"; ls -l "$B"
log "upload to Google Drive"
R="data-gdrive-unza_ac_zm:Server backups before Ubuntu upgrade/$D"
rclone copy "$B" "$R" --retries 5 --low-level-retries 20 --transfers 2 --stats 60s --stats-one-line
rclone check "$B" "$R" --one-way
log "BACKUP DONE: $B and $R verified"
