#!/bin/bash
# Copy the latest NETD backup to Google Drive (lighton.phiri@unza.ac.zm), verify it, keep ~60 days.
# rclone remote "data-gdrive-unza_ac_zm" (scope drive.file) in /root/.config/rclone/rclone.conf;
# backups land in "NETD portal backups/YYYY-MM-DD/". To add a destination, add another remote to REMOTES.
set -Eeuo pipefail
B=/var/backups/netd; LOG=/var/log/netd-backup.log; FOLDER="NETD portal backups"
REMOTES=(data-gdrive-unza_ac_zm)
trap 'echo "$(date -Is) upload FAILED (line $LINENO)" >>$LOG; exit 1' ERR
SRC=$(readlink -f "$B/latest"); D=$(basename "$SRC")
for R in "${REMOTES[@]}"; do
  rclone copy "$SRC" "$R:$FOLDER/$D" --retries 5 --low-level-retries 20
  rclone check "$SRC" "$R:$FOLDER/$D" --one-way
  rclone delete "$R:$FOLDER" --min-age 60d
  rclone rmdirs "$R:$FOLDER" --leave-root
  echo "$(date -Is) upload OK $R:$FOLDER/$D" >>$LOG
done
