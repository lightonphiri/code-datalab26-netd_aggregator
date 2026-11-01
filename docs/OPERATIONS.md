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
- `portal.sqlite3.gz`: the portal database: problem reports, admin accounts and the admin activity log.
- `csv-sources.tgz`: CSV files received from institutions (`harvester/uploads/`) and `harvester/sources.local.yml`. Restore it into `/opt/netd/harvester/` (`tar xzf csv-sources.tgz -C /opt/netd/harvester`).
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

## Metadata filling (FR-14, FR-48 to FR-53)
All commands run in `/opt/netd/harvester` as `netd` (`sudo -u netd .venv/bin/python -m netd.cli ...`). Anything that writes many rows runs under the harvest lock: prefix `flock -w 7200 run.lock`.

- **Status:** `text-report` (PDF text per source and status), `export-predictions /opt/netd/logs/predictions.csv`.
- **Extract PDF text** (new or changed records only): `extract-text --limit 500`; scanned PDFs: `ocr-text --limit 50` (about 20 s each at low priority). For the whole backlog, run batches as a transient unit so a disconnect does not stop them and the nightly harvest waits at most one batch:
  `sudo systemd-run --unit=netd-mltext --uid=netd --gid=netd --working-directory=/opt/netd/harvester --nice=10 /bin/bash -c 'for i in $(seq 1 15); do flock -w 7200 run.lock .venv/bin/python -m netd.cli extract-text --limit 500 || exit 1; done; for i in $(seq 1 80); do flock -w 7200 run.lock .venv/bin/python -m netd.cli ocr-text --limit 50 || exit 1; done'`
  Follow it with `journalctl -u netd-mltext -f`; stop it with `sudo systemctl stop netd-mltext`. Retry repository errors later with `extract-text --retry-failed`.
- **Predict, then apply:** `predict` (only records whose input changed; `--all` to recompute), then `reprocess` (process and index every source, no harvest). Always dry-run first on a copy: `sqlite3 netd.sqlite3 ".backup /opt/netd/logs/dry.sqlite3"`, then `process --db /opt/netd/logs/dry.sqlite3` and compare `report`.
- **Predictions from elsewhere** (e.g. a Colab notebook): JSON Lines with `record_id, field, model, version, value, confidence` (optional `evidence`, `input_hash`); `load-predictions FILE.jsonl`, then `reprocess`.
- **Thresholds:** `enrichers.yml` → `ml.show_threshold` (0.8), `ml.level_auto_exclude` (0.95), `ml.level_review_min` (0.6). After changing them, `reprocess`.
- **Gold standard and evaluation:** `gold-sample /opt/netd/logs/gold.csv --n 300` gives a stratified sample; annotators fill the `gold_*` columns from the PDFs (several values separated by `||`, `-` when the PDF does not say); `evaluate gold.csv` prints coverage, precision, recall and F1 per model and field.
- **Corrections from the shell** (the admin panel is the normal way): `correct unza-123456789-1000 supervisor "Henry J. Msango" --by lighton.phiri@unza.ac.zm --note "from acknowledgements"`; `correct <id> _scope exclude --by ... --note ...`; `uncorrect <id> <field>`.
- **The store is in WAL mode.** Open it only as `netd` (never as root): a root-owned `netd.sqlite3-wal` or `-shm` would stop the harvester. If that ever happens: stop writers, then `chown netd:netd /opt/netd/harvester/netd.sqlite3*`.

## Excluding records

The portal holds postgraduate work only (SRS FR-47). Records identified as below postgraduate level are left out automatically when processing. To leave out one record (for example a bachelor's report deposited in an ETD collection), add it to its source in `harvester/sources.yml` with a reason, release, and process and index that source (or wait for the nightly run):

```yaml
    exclude_records:
      - oai_id: "oai:rims.unza.ac.zm:123456789/8053"
        reason: "Bachelor of Laws dissertation deposited in the Theses and Dissertations community"
```

`netd.cli report` and the admin panel's source page list every excluded record and why. To bring a record back, remove its entry; the harvested metadata was never deleted.

## REST API

https://netd.ac.zm/api/v1 (SRS EI-6, FR-42 to FR-46; SDD §5.3; specification `portal/public/api/v1/openapi.yaml`). It reads Solr only, so it shows whatever the nightly index holds. `/api/v1/stats` and `/api/v1/institutions` are cached for 10 minutes. The export files are built in `portal/tmp/api_export/` when first requested and rebuilt when more than 6 hours old; deleting them is safe. Rate limits (120 requests a minute per address per endpoint, 20 exports an hour) are counted in the Rails cache and reset when the portal restarts. Any change to the API's fields must be made in the specification too.

## Admin panel

https://netd.ac.zm/admin, for the portal team (SRS FR-36 to FR-41; design in SDD §5.2). It shows every source's latest harvest and record counts, starts a harvest of one source ("Run now"), lists problem reports so they can be marked resolved with a note, takes CSV uploads (checked first, loaded only on confirmation), and keeps an activity log of every sign-in and change.

Accounts are managed on the server only, as root:

```
bash /opt/netd/deploy/ops/netd-user.sh add EMAIL=jane@unza.zm NAME="Jane Banda"   # prints a one-time password
bash /opt/netd/deploy/ops/netd-user.sh reset EMAIL=jane@unza.zm                   # new one-time password; signs out everywhere
bash /opt/netd/deploy/ops/netd-user.sh disable EMAIL=jane@unza.zm                 # or enable
bash /opt/netd/deploy/ops/netd-user.sh list
```

Give the one-time password to the person directly (not by email). They must change it when they first sign in. Sessions end after 2 hours of inactivity or 12 hours in total.

Restarting the portal (`systemctl restart netd-portal`, or a deployment) stops a harvest that was started from the panel; start it again, or leave it to the nightly run.


## Adding an institution that sends a CSV file

Normally this is done in the admin panel: **Upload CSV**, choose the institution (or a new HEA institution and its short name), check the file, then load it. The panel registers a new institution in `harvester/sources.local.yml` and keeps the file in `harvester/uploads/<id>/records.csv` (earlier files in `archive/`). The steps below do the same from the command line.

1. Check the file: `cd /opt/netd/harvester && sudo -u netd .venv/bin/python -m netd.cli csv-check FILE`. Send the listed problems back to the institution; rows with problems are skipped when loading.
2. Add a source to `harvester/sources.yml`, with `name` exactly as in `harvester/institutions.yml`:
   ```yaml
   - id: cbu
     name: Copperbelt University
     short_name: CBU
     loader: csv
     # either a file or folder on the server (default /opt/netd/harvester/uploads/<id>/) ...
     csv_path: /opt/netd/harvester/uploads/cbu
     # ... or a link the institution keeps current, read every night
     # csv_url: https://docs.google.com/spreadsheets/d/e/.../pub?output=csv
   ```
3. In `harvester/institutions.yml`, set the institution's `status: harvested` and `source: <id>`.
4. Release, then put the file in place (`sudo -u netd cp FILE /opt/netd/harvester/uploads/<id>/`) and run `netd.cli run --source <id>`. The nightly run picks up later changes to the file or link.

