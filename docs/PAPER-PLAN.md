# Paper plan: metadata filling for the Zambia National ETD Portal

**Status:** agreed with Lighton Phiri on November 1, 2026. **This is the final step of the project:** when the portal build is complete, the last session drafts the paper from this plan and the evidence logged below. Every hand-off note must carry this plan forward (section "Final step: the paper").

## Working framing
*Calibrated, evidence-grounded metadata extraction, distilled for a resource-constrained national ETD aggregator.* The contribution is not only the models but showing that a national aggregator in the Global South can fill missing ETD-MS metadata to a guaranteed precision with no paid APIs, no owned GPU and a 3.8 GB shared server.

Earlier DataLab work (Phiri 2020; Chipangila et al. 2021, 2023; Kasonde, Chisale and Phiri 2022–2024; Nyambe et al., in revision, preprint to be posted on arXiv) is background and related work, not the method.

## Method (as built, in order)
1. Rules baseline `titlepage-rules` (in production since November 1, 2026).
2. Gold standard: stratified sample (`netd.cli gold-sample`), annotated, with inter-annotator agreement; admin corrections as further labels.
3. Layout-aware parsing (e.g. Docling/Marker) and page-type classification of preliminary pages; vision-language OCR for scanned PDFs.
4. One schema-constrained, evidence-grounded LLM extraction pass (open-weight 7–14B, quantised); values without a verbatim evidence span are discarded.
5. Calibration (isotonic on gold; self-consistency, token probabilities, rules agreement) and thresholds chosen for target precision from risk–coverage curves.
6. Distillation into a small CPU model that runs nightly on the server.
7. Normalisation to authority lists: supervisors (name variants, ORCID), HEI units, HEA-accredited programmes, ISCED-F 2013 fields.
8. Embeddings for subjects, duplicates (FR-19) and search.
9. Active learning from corrections and the review list.

## Compute (no owned GPU, no paid APIs)
- **GPU work is a one-off backfill plus occasional retraining, never part of the nightly pipeline.** It runs on free notebook GPUs (Kaggle: about 30 GPU-hours a week, 12-hour sessions, background execution; Google Colab free tier as a second option), in resumable chunks that checkpoint to files, and comes back as JSON Lines through `netd.cli load-predictions`.
- **Nightly work is CPU-only on the server:** text extraction, Tesseract for any new scans, the rules model and the distilled model.
- **Fallback with no GPU at all:** a quantised small LLM via llama.cpp on a laptop CPU overnight (days, not hours, for the backfill); or train the student only on the gold standard and corrections.

## Evidence to log while building (needed to write the paper)
Keep this table up to date in every session; the paper is written from it.

| Date | Experiment / run | Data (n, institutions) | Hardware, time | Result (P/R/F1, coverage) | Where (commit, file) |
|---|---|---|---|---|---|
| November 1, 2026 | `titlepage-rules` v2 on first 171 UNZA texts (coverage only, no gold yet) | 171 UNZA | server CPU, about 3 s | coverage: degree level 64%, degree 63%, supervisor 36%, department 11%, faculty 16% | `titlepage.py` version 2 |
| November 1, 2026 | Gold standard: 2020 DataLab transcription of 3,267 UNZA ETDs (8 annotators; title, declaration, approval and acknowledgements pages); converted to `gold-unza-2020.csv`, split by hash of record id into dev 1,661 / test 1,606 | UNZA only | — | gold values: degree level 2,837, degree 2,814, supervisor 2,712, discipline 2,194, department 622. Caveat for the paper: 20 randomly drawn disagreements (from both halves) were inspected before the split was made | `work/`, `/opt/netd/logs/` |
| November 1, 2026 | `titlepage-rules` v9 on the **held-out test half** (threshold 0.8; recall counts records without text yet, OCR of scans still running) | 1,606 UNZA | server CPU | P / R / F1: degree level 0.991 / 0.478 / 0.645; degree 0.862 / 0.414 / 0.559; discipline 0.839 / 0.417 / 0.557; supervisor 0.797 / 0.234 / 0.362; department 0.963 / 0.243 / 0.388. Portal completeness after applying: supervisor 37.8% | `netd.cli evaluate` |
| November 1, 2026 | PDF text extraction backlog (text layer) | 5,925 records | server, 2 download threads, about 1 hour | text: UNZA 3,721, ZCAS 107, UNILUS 51, MU 11; scans: UNZA 1,455 (OCR ~18 s each on 2 shared CPUs); repository errors: UNZA 431, UNILUS 11 | `text-report` |
| November 1, 2026 | `titlepage-rules` v7 applied to the portal (threshold 0.8) | 3,905 texts | server CPU, about 8 minutes per full prediction run (before the word-count speed-up) | completeness, all sources: supervisor 0% → 34.7%, degree 17% → 62.3%, degree level 40% → 71.2%, department 0% → 4.7%; 3,366 records gained values; 2 records excluded as Bachelor's (both correct); 12/12 sampled new Doctoral labels correct; spot checks of 30 random values per version: about 27–28/30 correct at v4–v6 | `deploy/ops/netd-ml-apply.sh`, `/api/v1/stats` |
| November 1, 2026 | PDF text extraction backlog started | all records with PDFs | server, 2 threads, ~1.6 PDFs/s | about two-thirds of early UNZA PDFs are scans; ~15% of UNZA PDF links return HTTP 500 | `text-report` |

## Evaluation
Field-level P/R/F1 (normalised matching; people by surname + initial); risk–coverage curves and calibration error; cross-institution generalisation (train UNZA, test ZCAS, MU, UNILUS); born-digital vs scanned; ablations (front matter first, page classification, grounding check, distillation); facet counts before and after (discoverability); cost, time and energy per 1,000 ETDs on free and CPU hardware.

## Venue
To be decided with Lighton when drafting (digital libraries or document-analysis venue).
