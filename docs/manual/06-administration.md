# 6. System administration

Day-to-day work is done in the **admin panel** at `/admin`; server tasks use the `netd.cli` command line and the scripts in `deploy/ops/`. Command examples run on the server in `/opt/netd/harvester` as the `netd` user:

```bash
cd /opt/netd/harvester
sudo -u netd .venv/bin/python -m netd.cli <command> [options]
```

Any command that writes the staging store takes the harvest lock first, so it never overlaps the nightly run or a harvest started from the panel: `sudo -u netd flock -w 7200 run.lock .venv/bin/python -m netd.cli <command>`.

## 6.1 The admin panel

| Page | Path | Who | What |
|---|---|---|---|
| Dashboard | `/admin` | admin | each source's latest harvest, record counts, **Run now**; institutions not yet harvested and the weekly repository check |
| Source | `/admin/sources/<id>` | admin | runs, counts, excluded records and why |
| Problem reports | `/admin/reports` | admin | reports sent from record pages; mark resolved with a note |
| Upload CSV | `/admin/csv` | admin | check a CSV file from an institution, then load it |
| Records | `/admin/records` | admin | look up a record; correct a field; exclude or restore it |
| Degree-level review | `/admin/review` | admin | records a model thinks may be below postgraduate level |
| Duplicates | `/admin/duplicates` | admin | reject a match or choose the main record |
| Metadata quality | `/admin/quality` | admin, viewer | per-institution completeness and suggested improvements |
| Usage | `/admin/usage` | admin, viewer | searches, views, downloads, places; CSV |
| Reports | `/admin/etd-reports` | admin, viewer | reports per institution, by supervisor, custom; Excel and PDF |
| Activity log | `/admin/log` | admin | every action taken in the panel |

Sessions end after 2 hours of inactivity or 12 hours in total.

## 6.2 Accounts and roles

Accounts are created on the server only (as root), which keeps sign-up off the public site:

```bash
bash /opt/netd/deploy/ops/netd-user.sh add EMAIL=jane@example.ac NAME="Jane Banda"            # admin; prints a one-time password
bash /opt/netd/deploy/ops/netd-user.sh add EMAIL=x@regulator.example NAME="..." ROLE=viewer   # read-only
bash /opt/netd/deploy/ops/netd-user.sh role EMAIL=... ROLE=admin|viewer
bash /opt/netd/deploy/ops/netd-user.sh reset|disable|enable EMAIL=...
bash /opt/netd/deploy/ops/netd-user.sh list
```

Give the one-time password to the person directly. The **viewer** role (for the national regulator's staff) sees reports, metadata quality and usage only.

## 6.3 Sources and institutions

- `harvester/institutions.yml` lists **every institution expected to contribute**, with a status (`harvested`, `no-etds-yet`, `no-etd-collection`, `repository-unreachable`, `no-repository-known`). Institutions not harvested appear with 0 records.
- `harvester/sources.yml` lists the **sources harvested** (one per repository); `name` must equal the institution's `name` in `institutions.yml`.
- Sources added from the panel (CSV institutions) are kept in `harvester/sources.local.yml`.

**Adding a repository** (DSpace with OAI-PMH):

1. Check `<base>/oai/request?verb=Identify` and `?verb=ListSets`; find the sets that hold theses.
2. Look at a few records: `?verb=ListRecords&metadataPrefix=dim&set=<set>` (degree level, PDF links).
3. Add the source to `sources.yml` (see [chapter 7](07-configuration.md)), set the institution's `status: harvested` and `source: <id>` in `institutions.yml`, and deploy.
4. `flock -w 7200 run.lock .venv/bin/python -m netd.cli run --source <id> --full`, then `report`.

**Repository problems seen in practice** and what to ask the institution: OAI-PMH answers `noRecordsMatch` or HTTP 500 while the repository shows items → the DSpace OAI index is empty: run `[dspace]/bin/dspace oai import -c` and schedule `dspace oai import` nightly; HTTP 403 or no answer from outside the campus → open the repository to the internet; theses mixed with other items → a separate theses collection.

The weekly **repository check** (`check-repositories`, Mondays) probes every institution not yet harvested and reports changes on the dashboard and in the weekly email.

**Institutions without a repository** send a CSV file (template at `/netd-etd-template.csv`, column guide on Developer Resources). In the panel: **Upload CSV** → choose the institution → check → load. From the shell: `csv-check FILE`, then a source with `loader: csv` and `csv_path` or `csv_url`.

## 6.4 Harvesting schedule

| Timer | When (server time, UTC) | What |
|---|---|---|
| `netd-harvest.timer` | daily 02:30 | `netd.cli run` (harvest, PDF text and predictions for new records, process, dedup, index), then `netd.cli check` |
| `netd-backup.timer` | daily 04:15 | backup to `/var/backups/netd/` and the off-server copy |
| `netd-probe.timer` | every 15 minutes | the public site serves results |
| `netd-weekly.timer` | Mondays | repository check and weekly status email |

`systemctl list-timers 'netd-*'` shows the next runs. After the first harvest, runs are incremental. An unreachable repository is recorded as a failed run and does not stop the others; `check` then fails and an alert is sent.

## 6.5 Exclusions (postgraduate scope)

The portal holds postgraduate work only (`scope.degree_levels` in `sources.yml`). Records identified as below that level are left out when processing; records whose level cannot be identified are kept. To leave out one record, add it under its source with a reason:

```yaml
    exclude_records:
      - oai_id: "oai:repository.example.ac:123456789/8053"
        reason: "Bachelor's dissertation in the theses collection (checked May 4, 2027)"
```

then `process --source <id>` and `index` (or wait for the nightly run). A model can also propose exclusions (see [chapter 9](09-metadata-filling.md)); uncertain ones go to **Degree-level review**. The harvested record is never deleted: removing the entry brings it back. `report` and the source page list every exclusion.

## 6.6 Duplicates

`dedup` groups theses deposited more than once: same DOI, or near-identical titles with compatible authors and years at most 2 apart. One record is the main record (an administrator's choice, else the one with a PDF, the more complete one, or the later one); the others are listed under it. It runs after every `process`, `reprocess` and `run`; after running it by hand, run `index`. Decisions in **Duplicates** in the panel take effect at once.

## 6.7 Corrections

A correction always wins over harvested, derived and predicted values, and survives later harvests. Normally use **Records** in the panel. From the shell:

```bash
flock -w 7200 run.lock .venv/bin/python -m netd.cli correct <record-id> supervisor "Henry J. Msango" \
    --by you@example.ac --note "from the acknowledgements"
flock -w 7200 run.lock .venv/bin/python -m netd.cli correct <record-id> _scope exclude --by ... --note ...
.venv/bin/python -m netd.cli uncorrect <record-id> <field>
flock -w 7200 run.lock .venv/bin/python -m netd.cli reprocess
```

Department and supervisor **spelling variants** are merged automatically at indexing time (see [chapter 9](09-metadata-filling.md) and [chapter 7](07-configuration.md)); the original spellings stay searchable and are shown on the record page.

## 6.8 Reports

`/admin/etd-reports` builds reports from the search index: **per institution** (summary, then theses by year, degree level, year and level, type, faculty or school, faculty and department, and degree; optional usage: views and downloads, most viewed records, readers by country), **by supervisor**, and **custom** (filters, grouping by one or two fields, chosen columns, optional usage figures). Preview on screen, download as Excel or PDF (at most 1,000 rows per table in PDF).

## 6.9 Usage analytics

The portal counts usage itself, with no third-party trackers and no IP addresses, browser details or search words kept: daily counts of searches, record views, PDF downloads (through the portal's Download links), browsing, API and OAI-PMH requests, with country and approximate city from an offline database (DB-IP Lite, refreshed monthly by `deploy/ops/geoip-update.sh`). Crawlers, link previews, signed-in administrators and pages after the first page of results are not counted. Treat the figures as a lower bound on use. **Usage** in the panel shows 7, 30, 90 or 365 days and a CSV download.

## 6.10 Backups and restore

`deploy/ops/netd-backup.sh` writes `/var/backups/netd/YYYY-MM-DD/` (14 days kept) only if every step succeeds:

| File | Contents |
|---|---|
| `netd.sqlite3.gz` | the staging store: raw harvested XML, canonical records, predictions, corrections (the system of record) |
| `portal.sqlite3.gz` | portal database: accounts, activity log, problem reports, usage counts |
| `csv-sources.tgz` | CSV files from institutions and `sources.local.yml` |
| `solr-conf.tgz` | the Solr configset |
| `MANIFEST.txt`, `SHA256SUMS` | counts and checksums |

`deploy/ops/netd-backup-to-gdrive.sh` copies the folder off the server with rclone and verifies every file (`REMOTES` lists the destinations). The Solr index is not backed up (it is rebuilt in minutes), nor is `/opt/netd/portal.env` (keep its values in a password manager).

**Restore** (after `install-server.sh` and `deploy.sh` on a new server, if needed):

```bash
D=/var/backups/netd/2027-05-04 && cd $D && sha256sum -c SHA256SUMS
sudo systemctl stop netd-harvest.timer netd-portal
gunzip -c $D/netd.sqlite3.gz   | sudo -u netd tee /opt/netd/harvester/netd.sqlite3 >/dev/null
gunzip -c $D/portal.sqlite3.gz | sudo -u netd tee /opt/netd/portal/storage/production.sqlite3 >/dev/null
cd /opt/netd/harvester && sudo -u netd .venv/bin/python -m netd.cli index && sudo -u netd .venv/bin/python -m netd.cli check
sudo systemctl start netd-portal netd-harvest.timer
```

## 6.11 Alerts

Every NETD unit has `OnFailure=netd-alert@%n.service`, which emails the unit's status and its last 60 log lines through the SMTP account in `portal.env` (to `ALERT_TO`, else `SMTP_USER`). The probe alerts once per outage and once on recovery; the weekly status email confirms that the alert path works. Test it with `sudo systemctl start netd-alert@test.service`.

| Alert | First thing to do |
|---|---|
| `netd-harvest.service` failed | `journalctl -u netd-harvest -n 80`; `PROBLEM:` lines name the source; a repository that is down needs no action |
| `netd-backup.service` failed | `tail /var/log/netd-backup.log`; an authorisation error means the rclone token must be renewed |
| `netd-probe.service` failed | `systemctl status netd-portal netd-solr apache2`; restart what is down |
| `netd-solr` or `netd-portal` failed | `journalctl -u <unit> -n 100`, then `systemctl restart <unit>` |

## 6.12 Command-line reference

| Command | What it does |
|---|---|
| `harvest [--source ids] [--full] [--limit n]` | harvest raw records (incremental unless `--full`) |
| `process [--source ids] [--db path]` | crosswalk, rules, overlay of predictions and corrections, scope; `--db` on a copy for a dry run |
| `index [--solr url]` | write Solr from the canonical records |
| `run [--source ids] [--full]` | harvest, nightly metadata filling, process, dedup, index |
| `reprocess` | process and index every source without harvesting |
| `report` | counts, completeness and exclusions per source |
| `check [--max-age-hours n]` | health check used after the nightly run |
| `dedup` | recompute duplicate groups |
| `csv-check FILE` | check an institution's CSV file |
| `check-repositories` | probe institutions not yet harvested |
| `quality-report` | metadata quality figures for `/quality` |
| `extract-text`, `ocr-text`, `text-report` | PDF text cache ([chapter 9](09-metadata-filling.md)) |
| `predict`, `load-predictions`, `export-predictions` | model predictions |
| `gold-sample`, `evaluate [--strata]` | gold-standard evaluation |
| `correct`, `uncorrect` | hand corrections |

Configuration paths can be overridden with environment variables (`NETD_DB`, `NETD_SOLR`, `NETD_SOURCES_LOCAL`, `NETD_INSTITUTIONS`, `NETD_UPLOADS`, `NETD_LOGS`, `NETD_MODELS`, `NETD_OAI`).

## 6.13 Rules that prevent trouble

- The staging store is SQLite in **WAL mode**: open it only as `netd`, never as root (a root-owned `-wal` or `-shm` file stops the harvester; fix with `chown netd:netd /opt/netd/harvester/netd.sqlite3*`).
- Before a data change on the live store, dry-run on a copy: `sqlite3 netd.sqlite3 ".backup /opt/netd/logs/dry.sqlite3"`, then `process --db /opt/netd/logs/dry.sqlite3` and compare `report`.
- Long jobs (OCR backlogs, full predictions) run as transient units, so a dropped SSH session does not stop them: `sudo systemd-run --unit=<name> --uid=netd --gid=netd --working-directory=/opt/netd/harvester ...`, followed with `journalctl -u <name> -f`.
- Restarting the portal stops a harvest started from the panel; the next run finishes the job.
