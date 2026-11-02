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

The server (`portal`, Ubuntu 26.04.1 LTS since November 2, 2026) is shared with other services: OJS (`/ojs`), ZNRP (`/znrp`), the EMI Drupal site (emi.org.zm, `drupal_emiproject`), MySQL 8.4, Orthanc (custom build), Tomcat (OpenMRS) and nginx. NETD itself uses none of the system's Ruby, PHP or Java. Ruby, Python (uv) and Solr all live under `/opt/netd`; but Ruby is compiled against the system's libraries, so after an OS release upgrade it must be rebuilt (`deploy/ops/upgrade/rebuild-ruby.sh`).

**Before the next release upgrade, read "Ubuntu upgrade 20.04 → … → 26.04" below** (backups, shim for Orthanc, what broke and why).

### October 31, 2026

- **apt repaired.** `php8.1-intl` had been half-installed since June 16, 2025, from an Ubuntu 24.04 build that cannot run on 20.04. That left apt unable to install or upgrade anything. The half-installed package was removed, and `apt-get check` now passes.
- **OJS (`/ojs`) restored.** OJS had been failing with "Class Locale not found" because PHP 8.1 had no intl extension. The ondrej PPA no longer publishes builds for 20.04, so `intl.so` was compiled from the PHP 8.1.27 source against the system ICU 66 and installed as `/usr/lib/php/20210902/intl.so`, with `/etc/php/8.1/mods-available/intl.ini`. To undo this, run `phpdismod -v 8.1 intl` and restart Apache.

### Ubuntu upgrade 20.04 → 22.04 → 24.04 → 26.04 (November 2, 2026)

Done in session 05 on Lighton's instruction (November 1, 2026) without waiting for the other service owners, and without a ZAMREN snapshot. OJS is out of scope (Lighton, November 2, 2026: "ignore the OJS"); the EMI Drupal site is the one other application that must keep working. The scripts used are in `deploy/ops/upgrade/`.

**What had to be found out first (not in the earlier plan).**
- The custom Orthanc build (`orthanc-build.service`, user `emiproject`, binary and plugins under `/home/emiproject/work_package-2/pacs-orthanc/orthanc/`) links Boost 1.71, DCMTK 3.6.4, OpenSSL 1.1, ICU 66, libjsoncpp 1, protobuf 17 and others that 22.04 removes. The packaged `orthanc.service` (disabled) is a different install and was left disabled.
- NETD's Ruby (`/opt/netd/ruby`, built with ruby-build on 20.04) links OpenSSL 1.1 and libffi 7, so the portal would not start on 22.04 without a rebuild. Python (uv) and Solr are unaffected; Solr runs on the system OpenJDK 11, which every release up to 26.04 still ships.
- Tomcat (`/opt/tomcat`, OpenMRS) runs on OpenJDK 8, which 26.04 still ships (universe).
- MySQL: 8.0 on 22.04 and 24.04, **8.4 on 26.04**. All MySQL users already use `caching_sha2_password` (8.4 disables `mysql_native_password`).
- PHP: the ondrej PPA builds 8.1 for 22.04 and 24.04 but **has no 26.04 builds**; 26.04 ships PHP 8.5 only. The EMI site (Drupal 10.1.1) supported PHP up to 8.2, so it was upgraded to Drupal 10.6 and then 11 (below).

**Steps.**
1. Stopped the OCR unit (`netd-mltext`, idle: UNZA's repository was down) and the NETD timers (harvest, weekly, probe, backup). Timers come back after a reboot: stop them again after every reboot until the upgrade is finished.
2. Full backup (`upgrade-backup.sh`): consistent SQLite copies of both NETD stores, `mysqldump --all-databases`, archives of `/etc /root /usr/local /var/spool/cron /var/lib/orthanc /var/www`, `/opt` and `/home` (Orthanc stopped for 19 minutes for a consistent copy of its storage), package lists, `ldd` of Orthanc; 10.3 GiB in `/var/backups/upgrade-2026-11-02/` and on Drive in "Server backups before Ubuntu upgrade/2026-11-02" (verified with `rclone check`). **Uploads to Drive need `--drive-chunk-size 128M`**: with rclone's default 8 MB chunks the server managed about 0.3 MB/s, with 128 MB chunks about 13 MB/s.
3. Compatibility libraries (`compat-focal.sh`): the focal libraries that Orthanc, its plugins and NETD's Ruby link to (74 files, glibc and libstdc++ excluded) copied to `/opt/compat-focal/lib`, and a drop-in `compat-focal.conf` with `LD_LIBRARY_PATH` for `orthanc-build` and `netd-portal` only. This kept both running through every hop. Undo: delete the drop-in, `systemctl daemon-reload`, restart.
4. Each hop: `apt-get -s full-upgrade` (check for removals), `full-upgrade`, `do-release-upgrade -f DistUpgradeViewNonInteractive` as a transient unit (keeps existing configuration files), reboot, `upgrade-check.sh` (services, 14 URLs, versions, `netd.cli check`, libraries the shim still supplies; results in `/var/backups/upgrade-checks/`).
5. Nodesource's repository (Node 18 for focal) had been withdrawn and broke `apt-get update`; it was disabled (`nodesource.list.disabled-20261102`).

**Hop 1 (22.04.5, about 40 minutes plus reboot).** All services as before. PHP 8.1 then moved to the ondrej jammy builds (8.1.34, with the packaged `php8.1-intl`; the hand-built `intl.so` of October 31, 2026 removed) and PHP 7.4, 8.0 and 8.2 were purged (unused).
- **Two mistakes to avoid next time.** (a) `apt-get autoremove` after the release upgrade removed 352 packages, including the GNOME desktop (gdm3, X server): the upgrade had left them marked as automatically installed. No hosted service used them; the list is in `/var/backups/upgrade-checks/jammy-autoremoved-desktop-packages.txt` and `apt-get install ubuntu-desktop-minimal` brings a desktop back if anyone needs it. (b) Purging the generic `php-*` metapackages (which had moved to the PPA's default, 8.4) also purged `php-common` and with it all of PHP 8.1; it was reinstalled within minutes and the configuration compared with the backup (no custom settings had been lost). **Always simulate (`apt-get -s`) a purge or autoremove first.**
- The missed 04:15 backup ran at boot before Solr was ready and failed; `netd-backup.sh` now waits up to 3 minutes for Solr.

**Hop 2 (24.04.5, about 30 minutes plus reboot).** SSH refused connections for about 15 minutes in the middle of the upgrade (openssh moves to socket activation, `ssh.socket`); the upgrade itself runs in its transient unit regardless, and SSH came back before it finished. After the reboot: **the two `compat-focal.conf` drop-ins had gone** (the library directory was intact), so Orthanc and the NETD portal failed until they were recreated; and Orthanc then stopped on "Inexistent file" because DCMTK 3.6.4's DICOM dictionary (`/usr/share/libdcmtk14/dicom.dic`) had left with its package. The newer `libdcmtk17` dictionary is rejected by the old parser, so the file was taken from the focal package `libdcmtk14_3.6.4-2.1ubuntu0.2_amd64.deb` (in `/opt/compat-focal/debs/`, extracted to `/opt/compat-focal/share/libdcmtk14`, symlinked from `/usr/share/libdcmtk14`). `compat-focal.sh` now does all of this and should be re-run after every hop. `/etc/hosts` lacked the host name (`127.0.1.1 portal` added; sudo had warned "unable to resolve host").
Then PHP 8.3 (24.04's own) was installed, Apache and the CLI switched to it, the EMI site moved to Drupal 11 (below), and PHP 8.1 was purged (simulated first: 12 packages, nothing else). The generic metapackages (`php`, `php-cli`, `php-mysql`, … `libapache2-mod-php`) were installed so that the 26.04 hop moves PHP to 8.5 by itself.

**Hop 3 (26.04.1, about 26 minutes plus reboot; kernel 7.0).** SSH again refused connections for about 10 minutes mid-upgrade; classic sudo (1.9.17) was kept. MySQL 8.0 → 8.4.11 in place without changes; PHP 8.3 → 8.5.4 through the metapackages; Java 8 and 11, Solr, Tomcat/OpenMRS, nginx unchanged in behaviour. The drop-ins survived this hop and Orthanc started on the shim.
- **Apache had no PHP module after the hop**: the release upgrade removed `libapache2-mod-php8.3` (whose module was the enabled one) and installed `libapache2-mod-php8.5` without enabling it, so from 07:19 to 07:28 UTC Apache served `.php` files as plain text (EMI's home page showed Drupal's `index.php` source, which holds no secrets). The access log for 07:05–07:28 (5,617 requests) has **no request for `settings.php`, `config.inc.php`, `.env` or SQL files**, so no credentials were exposed. Fixed with `a2enmod php8.5`. Next time: check `apache2ctl -M | grep php` straight after the hop, before anything else.
- NETD's Ruby was rebuilt against OpenSSL 3.5 (`rebuild-ruby.sh`) and the portal's shim removed; the harvester venv was recreated (uv's own Python 3.12). A first attempt built Ruby in `/opt/netd/ruby-new` and renamed it, which fails (Ruby records its install prefix in its binstubs and `libruby.so` path): the portal was down for about 2 minutes until the old build was put back; the script now builds in place and restores the old build if the build fails.
- Orthanc (custom build, owner: EMI project) still runs on the shim: 17 of its libraries exist only in `/opt/compat-focal/lib`. The lasting fix is to rebuild it from source on 26.04 (backlog).

### EMI Drupal site (emi.org.zm): Drupal 10.1.1 → 10.6.20 → 11.4.11 (November 2, 2026)

Lighton asked for the EMI site (the one other application that must keep working) to be upgraded so that it runs on 26.04's PHP 8.5; Drupal 10 also reaches end of life in December 2026. Each step was rehearsed on a staging copy (`/var/www/drupal_emiproject-staging`, database `drupal_emiproject_staging`, Apache vhost `emi-staging` on 127.0.0.1:8089 only), compared with live (status codes, links, images and headings of the main pages, assets), then applied to live in maintenance mode with a local copy of the site and database first (`/var/backups/emi-pre-d10-20261102/`, `/var/backups/emi-pre-d11-20261102/`).
- **Drupal 10.6.20 on PHP 8.1** (`emi-d10-update.sh`; live 04:44–04:50 UTC, about 6 minutes in maintenance). The site was Composer-based, but 24 contrib modules had been copied into `web/modules/` by hand; they are now required in `composer.json` at Drupal 11-ready versions and live in `web/modules/contrib/` (the old copies are in `/var/backups/emi-removed-modules-20261102/`). Uninstalled (unused or no Drupal 11 release): `ckeditor` (CKEditor 4; both text formats already used CKEditor 5), `ckeditor_bootstrap_table` (no tables in any body), `quicktabs` and `bootstrap_quicktabs` (no Quick Tabs instances), `html_head` (it held only the Google site-verification tag, now in Metatag's `metatag_verification`). Honeypot's update hooks 8103 and 8104 had never been run on live, so it went through 2.1.4 before 2.2. Themes edux and thex 11.0.0 (the search icon is now a font icon).
- **Drupal 11.4.11 on PHP 8.3** (`emi-d11-update.sh`; live 06:49–06:52 UTC, about 3 minutes in maintenance): `tour` uninstalled (removed from core in Drupal 11), Drush 13. Composer 2.11 blocks plugins not listed in `allow-plugins`; **`symfony/runtime` must be allowed**, because Drupal 11.4's `index.php` loads `vendor/autoload_runtime.php`, which that plugin writes (the first staging attempt returned 500 without it).
- `web/sites/default` is read-only (555): the scripts open it for Composer's scaffold step and close it again.
- Found, not changed (for the site's owners): the site has been failing to send email for some time ("Error sending email", several times a day); Backup and Migrate's daily schedule fails because no private file system path is set (`$settings['file_private_path']`); the status report flags trusted host settings as not configured; a disabled block refers to a deleted view (`notices`).

## Metadata filling (FR-14, FR-48 to FR-53)
A step-by-step, runnable explanation of everything below is in `notebooks/netd26-03-ml_metadata_filling-walkthrough.ipynb`.

All commands run in `/opt/netd/harvester` as `netd` (`sudo -u netd .venv/bin/python -m netd.cli ...`). Anything that writes many rows runs under the harvest lock: prefix `flock -w 7200 run.lock`.

- **Status:** `text-report` (PDF text per source and status), `export-predictions /opt/netd/logs/predictions.csv`.
- **Extract PDF text** (new or changed records only): `extract-text --limit 500`; scanned PDFs: `ocr-text --limit 50` (about 20 s each at low priority). For the whole backlog, run batches as a transient unit so a disconnect does not stop them and the nightly harvest waits at most one batch:
  `sudo systemd-run --unit=netd-mltext --uid=netd --gid=netd --working-directory=/opt/netd/harvester --nice=10 /bin/bash -c 'for i in $(seq 1 15); do flock -w 7200 run.lock .venv/bin/python -m netd.cli extract-text --limit 500 || exit 1; done; for i in $(seq 1 80); do flock -w 7200 run.lock .venv/bin/python -m netd.cli ocr-text --limit 50 || exit 1; done'`
  Follow it with `journalctl -u netd-mltext -f`; stop it with `sudo systemctl stop netd-mltext`. Retry repository errors later with `extract-text --retry-failed`.
- **Predict and apply safely in one go:** `sudo systemd-run --unit=netd-mlapply --uid=netd --gid=netd /opt/netd/deploy/ops/netd-ml-apply.sh` runs `predict`, a dry run on a copy, and `reprocess` under the lock only if the dry run excludes at most 10 records on a model's say (`MAX=` to change); follow with `journalctl -u netd-mlapply`.
- **Predict, then apply (by hand):** `predict` (only records whose input changed; `--all` to recompute), then `reprocess` (process and index every source, no harvest). Always dry-run first on a copy: `sqlite3 netd.sqlite3 ".backup /opt/netd/logs/dry.sqlite3"`, then `process --db /opt/netd/logs/dry.sqlite3` and compare `report`.
- **Predictions from elsewhere** (e.g. a Colab notebook): JSON Lines with `record_id, field, model, version, value, confidence` (optional `evidence`, `input_hash`); `load-predictions FILE.jsonl`, then `reprocess`.
- **Thresholds:** `enrichers.yml` → `ml.show_threshold` (0.8), `ml.level_auto_exclude` (0.95), `ml.level_review_min` (0.6). After changing them, `reprocess`.
- **Gold standard and evaluation:** `gold-sample /opt/netd/logs/gold.csv --n 300` gives a stratified sample; annotators fill the `gold_*` columns from the PDFs (several values separated by `||`, `-` when the PDF does not say); `evaluate gold.csv` prints coverage, precision, recall and F1 per model and field.
- **Corrections from the shell** (the admin panel is the normal way): `correct unza-123456789-1000 supervisor "Henry J. Msango" --by lighton.phiri@unza.ac.zm --note "from acknowledgements"`; `correct <id> _scope exclude --by ... --note ...`; `uncorrect <id> <field>`.
- **The store is in WAL mode.** Open it only as `netd` (never as root): a root-owned `netd.sqlite3-wal` or `-shm` would stop the harvester. If that ever happens: stop writers, then `chown netd:netd /opt/netd/harvester/netd.sqlite3*`.

## Fields of study (OpenAlex Topics, FR-54 to FR-57)
- The model `openalex-fos` runs with the other models (`predict`, nightly); its embedding model is downloaded once to `/opt/netd/harvester/models/fastembed` (about 90 MB).
- **Rebuild the model** (e.g. a new OpenAlex taxonomy): on the server, `sudo -u netd .venv/bin/python tools/openalex_training.py /opt/netd/harvester/models/openalex --per-subfield 120 --mailto lighton.phiri@unza.ac.zm` (OpenAlex allows a small anonymous daily budget per address; with a free key add `--api-key`); copy `taxonomy.json` and `works.jsonl` to a machine with spare CPU and run `python tools/train_fieldofstudy.py DATA_DIR netd/ml/models/data/openalex-fos-v<N>.npz --report ...` (about 25 minutes on 2 CPUs; embeddings are cached for later runs); bump `VERSION` and the file names in `netd/ml/models/fieldofstudy.py`, copy the taxonomy to `netd/ml/models/data/openalex-taxonomy.json`, release, then run `deploy/ops/netd-ml-apply.sh`.
- Thresholds: `SUBFIELD_MIN`, `SECOND_MIN`, `FIELD_MIN` in `fieldofstudy.py` (a change needs a new `VERSION`).

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


## Onboarding an institution with a repository

1. Look at the admin dashboard's "Institutions not yet harvested" table (or `sudo -u netd .venv/bin/python -m netd.cli check-repositories` in `/opt/netd/harvester`; the same check runs every Monday before the weekly email, which lists any changes).
2. When a repository is reachable and its ETD sets list records: check `?verb=ListSets`, a sample of `?verb=ListRecords&metadataPrefix=dim&set=<set>` (degree level, postgraduate only, PDF links via `ore`), then add a source to `harvester/sources.yml` with `sets` limited to the ETD collections and `name` exactly as in `institutions.yml`; set `status: harvested` and `source:` there; release; `netd.cli run --source <id>` under `flock -w 7200 run.lock`. Record the result in the SRS verification table.
3. Common repository-side problems (seen November 1, 2026) and what to ask the institution: OAI-PMH answers "noRecordsMatch" or HTTP 500 while the repository shows items → run `[dspace]/bin/dspace oai import -c` and schedule `dspace oai import` nightly; 403 or no answer from outside the campus → open the repository to the internet; theses mixed with articles and undergraduate projects → move them to dedicated collections. The public guide `https://netd.ac.zm/contribute` says the same for librarians.

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

