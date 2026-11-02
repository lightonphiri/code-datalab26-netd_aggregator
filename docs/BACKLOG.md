# Backlog: feature enhancements and bug fixes

Running list for the Zambia National ETD Portal. Add items as they come up (any session, or Lighton between sessions);
a "Features and fixes" session works through them. When an item is done, move it to "Done" with the date and commit.
Items that change an evaluated component (text extraction, OCR, models, the overlay) must also be logged in
`docs/PAPER-PLAN.md`; after the paper's frozen version is tagged, they are reported as post-paper changes only.

## Open

| Added | Item | Type | Notes |
|---|---|---|---|
| November 1, 2026 | Duplicate detection (SRS FR-19), embeddings later | Feature | Same thesis in two repositories or twice in one |
| November 1, 2026 | Faculty → department browsing (FR-25) | Feature | |
| November 1, 2026 | Usage analytics | Feature | Privacy-friendly, no third-party trackers |
| November 1, 2026 | Email alerts, phase 2 (FR-60) | Feature | After the HEA handover: double opt-in, weekly digest, unsubscribe; needs a portal sending address (ZAMREN or HEA) and a privacy notice (Data Protection Act 2021) |
| November 1, 2026 | Public per-institution quality figures (FR-28) | Feature | Only once agreed with HEA; one switch in `QualityController` |
| November 1, 2026 | NDLTD and registry registration | Feature | After more HEIs have OAI-PMH providers |
| November 1, 2026 | Modern metadata models (layout-aware parsing, VLM OCR on Kaggle, grounded LLM extraction, calibration, distillation) | Feature | See `docs/PAPER-PLAN.md` |
| November 1, 2026 | Field-of-study in-domain labels and retraining (FR-57) | Feature | Discipline names and repository headings mapped to subfields; annotated portal sample |
| November 1, 2026 | Gold standard for ZCAS, UNILUS and MU (`gold-sample`) | Feature | Needed for cross-institution evaluation |
| November 2, 2026 | LAMU: 2 MPH theses via JSPUI + GetRecord if its OAI index is not rebuilt | Feature | Low value; prefer LAMU running `dspace oai import -c` (via HEA) |
| November 2, 2026 | Orthanc (custom build of the EMI project) still runs on the focal-library shim after the 26.04 upgrade: rebuild it from source on 26.04 (or move to the packaged Orthanc 1.12 with its plugins), then delete `/opt/compat-focal` and the `orthanc-build` drop-in | Fix (server) | 17 of its libraries exist only in `/opt/compat-focal/lib` (OpenSSL 1.1 among them: no security updates). Source tree `/home/emiproject/work_package-2/pacs-orthanc/orthanc/` (mainline of September 1, 2023); see `docs/OPERATIONS.md` |
| November 2, 2026 | EMI Drupal site: email sending has been failing ("Error sending email", several times a day); Backup and Migrate's daily schedule fails (no private file path set); trusted host settings not configured | Fix (EMI site) | Found during the Drupal 11 upgrade; not changed. Set `$settings['file_private_path']` outside `web/` and `$settings['trusted_host_patterns']` for emi.org.zm; check the SMTP module settings |
| November 2, 2026 | OJS (`/ojs`, 3.4.0-5) now runs on PHP 8.5, beyond what OJS 3.4 supports | Note | Out of scope (Lighton, November 2, 2026); it answered normally after the upgrade, untested beyond that |
| November 2, 2026 | After the next OS change, check `apache2ctl -M` for the PHP module first | Fix (procedure) | In the upgrade checklist (`deploy/ops/upgrade/upgrade-check.sh` prints it) |

## Done

| Date | Item | Commit |
|---|---|---|
| November 2, 2026 | Server upgraded to Ubuntu 26.04.1 LTS; NETD's Ruby rebuilt against OpenSSL 3.5; venv recreated | Session 05 release, November 2, 2026 |
| November 2, 2026 | EMI Drupal site 10.1.1 → 11.4.11 (PHP 8.5-ready; contrib under Composer) | Server only (not in this repository); scripts in `deploy/ops/upgrade/` |
| November 2, 2026 | `ocr-resume.sh` kept in the repository (`deploy/ops/`) | Session 05 release |
| November 2, 2026 | Nightly backup no longer fails when it runs at boot before Solr is ready | Session 05 release |
| November 2, 2026 | One unreachable repository no longer stops the nightly run | f594ec8 |
| November 1, 2026 | OCR keeps PDFs queued during repository outages | 41ad6e5 |
