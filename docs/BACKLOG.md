# Backlog: feature enhancements and bug fixes

Running list for the Zambia National ETD Portal. Add items as they come up (any session, or Lighton between sessions);
a "Features and fixes" session works through them. When an item is done, move it to "Done" with the date and commit.
Items that change an evaluated component (text extraction, OCR, models, the overlay) must also be logged in
`docs/PAPER-PLAN.md`; after the paper's frozen version is tagged, they are reported as post-paper changes only.

## Open

| Added | Item | Type | Notes |
|---|---|---|---|
| November 1, 2026 | Email alerts, phase 2 (FR-60) | Feature | After the HEA handover: double opt-in, weekly digest, unsubscribe; needs a portal sending address (ZAMREN or HEA) and a privacy notice (Data Protection Act 2021) |
| November 1, 2026 | Public per-institution quality figures (FR-28) | Feature | Only once agreed with HEA; one switch in `QualityController` |
| November 1, 2026 | NDLTD and registry registration | Feature | After more HEIs have OAI-PMH providers |
| November 1, 2026 | Modern metadata models (layout-aware parsing, VLM OCR on Kaggle, grounded LLM extraction, calibration, distillation) | Feature | See `docs/PAPER-PLAN.md` |
| November 1, 2026 | Field-of-study in-domain labels and retraining (FR-57) | Feature | Discipline names and repository headings mapped to subfields; annotated portal sample |
| November 1, 2026 | Gold standard for ZCAS, UNILUS and MU (`gold-sample`) | Feature | Needed for cross-institution evaluation |
| November 2, 2026 | LAMU: 2 MPH theses via JSPUI + GetRecord if its OAI index is not rebuilt | Feature | Low value; prefer LAMU running `dspace oai import -c` (via HEA) |
| November 2, 2026 | Orthanc (custom build of the EMI project) still runs on the focal-library shim after the 26.04 upgrade: rebuild it from source on 26.04 (or move to the packaged Orthanc 1.12 with its plugins), then delete `/opt/compat-focal` and the `orthanc-build` drop-in | Fix (server) | **Separate session: hand-off `handoff-emiz26-01-orthanc_rebuild.zip`** (Lighton, November 2, 2026: radical customisation). 17 of its libraries exist only in `/opt/compat-focal/lib` (OpenSSL 1.1 among them: no security updates). Source tree `/home/emiproject/work_package-2/pacs-orthanc/orthanc/` (mainline of September 1, 2023); see `docs/OPERATIONS.md` |
| November 2, 2026 | OJS (`/ojs`, 3.4.0-5) now runs on PHP 8.5, beyond what OJS 3.4 supports | Note | Out of scope (Lighton, November 2, 2026); it answered normally after the upgrade, untested beyond that |
| November 2, 2026 | After the next OS change, check `apache2ctl -M` for the PHP module first | Fix (procedure) | In the upgrade checklist (`deploy/ops/upgrade/upgrade-check.sh` prints it) |
| November 2, 2026 | Duplicate detection across institutions by embeddings (titles in other words, translated titles) | Feature | FR-19 now matches DOI and near-identical titles; no cross-institution duplicate exists yet |
| November 2, 2026 | `www.emi.org.zm` has no DNS record | Note | Outside our control (EMI project's DNS); the site answers on emi.org.zm |
| November 2, 2026 | Error analysis of born-digital supervisor misses (recall 0.42 with text available) | Feature (paper) | Sample misses where the gold has a supervisor and the text names one; separate pattern gaps from signature-only names |
| November 2, 2026 | rclone Google Drive access for the backups (NETD and DataLab website servers): check what the remotes actually authenticate with (Lighton has an app password for rclone; Drive remotes normally use an OAuth token) and move to an own OAuth client if they still use rclone's shared one | Fix (late session) | Deferred to one of the last sessions (Lighton, November 2, 2026); backups work today |
| November 2, 2026 | Usage figures for the paper and for HEA: monthly summary from `/admin/usage.csv` (views and downloads per institution) | Feature (paper) | Counting started November 2, 2026; needs some months of data |
| November 2, 2026 | Popular search terms without storing what one person searched: count a term only once it has been searched on several days, or keep only the facet values chosen | Feature | Not built: FR-61 stores no search words (privacy) |
| November 2, 2026 | Department names that are really different units or wrong faculty pairs from the model ("Agricultural Sciences / Department of Public Health", "Education / Department of Community Medicine") | Fix (model output) | Seen on `/browse`; from `titlepage-rules` departments read from title pages. Changes an evaluated component: log in `docs/PAPER-PLAN.md` |
| November 2, 2026 | Network outage: netd.ac.zm, emi.org.zm and datalab.unza.zm unreachable from outside (HTTPS and SSH time out) from about 10:15 UTC, while UNZA's DNS has been down since November 1 | Note | Upstream (UNZA/ZAMREN network); outside our control. Still down at 11:27 UTC. Session 08: check the 1da3c26 deploy, then reprocess and reindex UNZA for FR-62 |

## Done

| Date | Item | Commit |
|---|---|---|
| November 2, 2026 | Usage analytics (FR-61): own daily counts (no trackers, no IPs or search words), `/admin/usage` with CSV, counted PDF links, FAQ note | e80a8cf, 50829a5 |
| November 2, 2026 | Blacklight search history pruned to one day nightly (540,539 rows in three days) | 1da3c26 |
| November 2, 2026 | Department name variants merged per institution at index time (FR-62): UNZA 94 → 80 names | 1da3c26 |
| November 2, 2026 | UNZA collections that are not Schools: "Library" (80 theses) → Education / Department of Library and Information Studies; journal and project collections → no faculty; Ministry of Health waste plan excluded (`set_units`, `exclude_records`) | 1da3c26 |
| November 2, 2026 | EMI Drupal site email works (Google SMTP, own app password) | Server only (`docs/OPERATIONS.md`) |
| November 2, 2026 | Exposed NETD alert app password revoked; new one per service; test alert received | Server only (`docs/OPERATIONS.md`, "SMTP app passwords") |
| November 2, 2026 | Browse by faculty and department (FR-25), `/browse` | 0056cf2 |
| November 2, 2026 | Duplicate detection (FR-19): listed once, copies linked, admin decisions, API 1.5.0 | a8605f6 |
| November 2, 2026 | EMI Drupal site: trusted host patterns and private file path; Backup and Migrate works again | Server only (`docs/OPERATIONS.md`, EMI site follow-up) |
| November 2, 2026 | `release.sh` stops when the package cannot be unpacked and checks that GitHub has HEAD (stale git lock had hidden this) | Laptop `access/release.sh` (not in the repository) |
| November 2, 2026 | Evaluation by kind of PDF text (`evaluate --strata`); apply guard counts only new exclusions; OCR resume finishes the pipeline itself; `pypdf[crypto]` | a9e951c |
| November 2, 2026 | Server upgraded to Ubuntu 26.04.1 LTS; NETD's Ruby rebuilt against OpenSSL 3.5; venv recreated | Session 05 release, November 2, 2026 |
| November 2, 2026 | EMI Drupal site 10.1.1 → 11.4.11 (PHP 8.5-ready; contrib under Composer) | Server only (not in this repository); scripts in `deploy/ops/upgrade/` |
| November 2, 2026 | `ocr-resume.sh` kept in the repository (`deploy/ops/`) | Session 05 release |
| November 2, 2026 | Nightly backup no longer fails when it runs at boot before Solr is ready | Session 05 release |
| November 2, 2026 | One unreachable repository no longer stops the nightly run | f594ec8 |
| November 1, 2026 | OCR keeps PDFs queued during repository outages | 41ad6e5 |
