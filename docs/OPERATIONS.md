# NETD operations guide

How the Zambia National ETD Portal (https://netd.ac.zm/) is kept running: schedules, backups, alerts, restore and server maintenance. Times below are server time (UTC); Lusaka is UTC+2.

## Schedule

| Unit | When (UTC) | What it does |
|---|---|---|
| `netd-harvest.timer` | daily 02:30 (+ up to 20 min) | harvest → process → index all sources, then `netd.cli check` (which also asks the OAI-PMH provider at http://127.0.0.1:3010/oai for `Identify`) |
| `netd-backup.timer` | daily 04:15 | server backup to `/var/backups/netd/`, then copy to Google Drive |
| `netd-probe.timer` | every 15 min | checks that https://netd.ac.zm/ returns search results |
| `netd-weekly.timer` | Mondays 06:00 | weekly status email |

`systemctl list-timers 'netd-*'` shows the next and last run of each.

## Alerts

Every NETD unit has `OnFailure=netd-alert@%n.service`, which runs `deploy/ops/netd-alert.py` and emails the unit's status and last 60 log lines. Mail is sent through the SMTP account in `/opt/netd/portal.env` (`SMTP_USER`, `SMTP_PASSWORD`). It goes to `ALERT_TO` if that is set in the same file, otherwise to `SMTP_USER`.

| Email subject | Meaning | First thing to do |
|---|---|---|
| NETD ALERT: netd-harvest.service failed | a source failed or is more than 30 hours old, or the search index disagrees with the staging store | `journalctl -u netd-harvest -n 80`; the `PROBLEM:` lines name the source. A repository that is temporarily down needs no action (the next run is incremental). |
| NETD ALERT: netd-backup.service failed | the server backup or the Drive upload failed | `tail /var/log/netd-backup.log`. An "upload FAILED" with an authorisation error means the Drive token must be renewed (see below). |
| NETD ALERT: netd-probe.service failed | the public site is not serving results (sent once per outage) | `systemctl status netd-portal netd-solr apache2`; restart what is down. A "NETD recovered" email follows when the site is back. |
| NETD ALERT: netd-solr / netd-portal failed | the service crashed repeatedly and systemd gave up | `journalctl -u <unit> -n 100`, then `systemctl restart <unit>` |
| NETD weekly status | sent every Monday | if it stops arriving, the alert path itself is broken: check `portal.env` and the SMTP password |

Test the alert path at any time with `sudo systemctl start netd-alert@test.service`.

## Backups

`deploy/ops/netd-backup.sh` writes `/var/backups/netd/YYYY-MM-DD/`. If any step fails, the folder from the previous night is left untouched. It contains:

- `netd.sqlite3.gz`: the staging store, holding the untouched OAI-PMH XML and the canonical records. This is the system of record.
- `portal.sqlite3.gz`: the portal database, which holds the problem reports.
- `solr-conf.tgz`: the Solr configset in use.
- `MANIFEST.txt`: record counts per source, the Solr document count and the deployed version.
- `SHA256SUMS`: checksums of the files above.

Fourteen days are kept on the server. `deploy/ops/netd-backup-to-gdrive.sh` then copies the folder to Google Drive (account lighton.phiri@unza.ac.zm, folder **NETD portal backups**, one dated subfolder per night) using the rclone remote `data-gdrive-unza_ac_zm`. It checks every file against its checksum and keeps about 60 days. Both scripts log to `/var/log/netd-backup.log`; a good night has one `backup OK` and one `upload OK` line.

The Solr index is not copied, because it can be rebuilt from the staging store in a few minutes. `/opt/netd/portal.env` holds secrets and is deliberately left out; keep its values in your password manager.

The rclone remote uses the `drive.file` scope, so it can only see files it created. Its token is in `/root/.config/rclone/rclone.conf`, which is the same remote used by the DataLab website server. If Google revokes it, run `sudo rclone config reconnect data-gdrive-unza_ac_zm:` on a machine with a browser and copy the resulting `rclone.conf` to both servers.

## Restore

On the NETD server, or on a fresh one after running `deploy/install-server.sh` and `deploy/deploy.sh`:

```bash
D=/var/backups/netd/latest          # or: rclone copy "data-gdrive-unza_ac_zm:NETD portal backups/2026-10-31" /tmp/r && D=/tmp/r
cd $D && sha256sum -c SHA256SUMS
sudo systemctl stop netd-harvest.timer netd-portal
gunzip -c $D/netd.sqlite3.gz   | sudo -u netd tee /opt/netd/harvester/netd.sqlite3 >/dev/null
gunzip -c $D/portal.sqlite3.gz | sudo -u netd tee /opt/netd/portal/storage/production.sqlite3 >/dev/null
cd /opt/netd/harvester && sudo -u netd .venv/bin/python -m netd.cli index && sudo -u netd .venv/bin/python -m netd.cli check
sudo systemctl start netd-portal netd-harvest.timer
```

`netd.cli check` must print `check: OK`, and the per-source counts should match `MANIFEST.txt`.

## Server maintenance

The server (`portal`, Ubuntu 20.04.6 LTS) is shared with other services: OJS (`/ojs`), ZNRP (`/znrp`), a Drupal site (`drupal_emiproject`), MySQL, Orthanc, Tomcat and nginx. NETD itself uses none of the system's Ruby, PHP or Java. Ruby, Python (uv) and Solr all live under `/opt/netd`, so an OS upgrade affects NETD only through Apache and system libraries.

### October 31, 2026

- **apt repaired.** `php8.1-intl` had been half-installed since June 16, 2025, from an Ubuntu 24.04 build that cannot run on 20.04. That left apt unable to install or upgrade anything. The half-installed package was removed, and `apt-get check` now passes.
- **OJS (`/ojs`) restored.** OJS had been failing with "Class Locale not found" because PHP 8.1 had no intl extension. The ondrej PPA no longer publishes builds for 20.04, so `intl.so` was compiled from the PHP 8.1.27 source against the system ICU 66 and installed as `/usr/lib/php/20210902/intl.so`, with `/etc/php/8.1/mods-available/intl.ini`. To undo this, run `phpdismod -v 8.1 intl` and restart Apache.

### Ubuntu upgrade plan (not yet done)

Ubuntu 20.04 stopped receiving standard security updates in May 2025. The path is 20.04 → 22.04 → 24.04, one release at a time with `do-release-upgrade`. It needs a maintenance window of about two hours, because it affects the other services listed above.

1. Agree a window with the owners of OJS, ZNRP and the EMI Drupal site, and ask ZAMREN for a VM snapshot just before it (the only quick way back).
2. The night before, take a NETD backup and check that it reached Drive. Also take a MySQL dump of all databases and an archive of `/var/www` and `/etc`.
3. Upgrade 20.04 → 22.04. Then reinstall PHP from the ondrej PPA for jammy (with `php8.1-intl`) and remove the hand-built `intl.so`. Check OJS, ZNRP, EMI and NETD.
4. Upgrade 22.04 → 24.04 the same way.
5. For NETD only: `systemctl restart netd-solr netd-portal`, then run `netd.cli check`. Ruby and Solr under `/opt/netd` do not change. If the system's Python moves, rebuild the harvester venv with `deploy/deploy.sh` (uv provides its own Python 3.12).
