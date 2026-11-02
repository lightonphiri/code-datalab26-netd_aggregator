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
| November 2, 2026 | Keep `ocr-resume.sh` in the repository (`deploy/ops/`) | Fix | Now only in `/opt/netd/logs/` |

## Done

| Date | Item | Commit |
|---|---|---|
| November 2, 2026 | One unreachable repository no longer stops the nightly run | f594ec8 |
| November 1, 2026 | OCR keeps PDFs queued during repository outages | 41ad6e5 |
