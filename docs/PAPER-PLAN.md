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
8. Standard fields of study for every record from OpenAlex Topics (FR-54 to FR-57; built November 1, 2026): embeddings + linear classifier trained on OpenAlex-labelled works, hierarchical back-off; next: tune thresholds, add repository keywords as input, annotate portal records, compare with fine-tuned encoders; embeddings reused for duplicates (FR-19) and search.
9. Active learning from corrections and the review list.

## Compute (no owned GPU, no paid APIs)
- **GPU work is a one-off backfill plus occasional retraining, never part of the nightly pipeline.** It runs on free notebook GPUs (Kaggle: about 30 GPU-hours a week, 12-hour sessions, background execution; Google Colab free tier as a second option), in resumable chunks that checkpoint to files, and comes back as JSON Lines through `netd.cli load-predictions`.
- **Nightly work is CPU-only on the server:** text extraction, Tesseract for any new scans, the rules model and the distilled model.
- **Fallback with no GPU at all:** a quantised small LLM via llama.cpp on a laptop CPU overnight (days, not hours, for the backfill); or train the student only on the gold standard and corrections.

## Evidence to log while building (needed to write the paper)
Keep this table up to date in every session; the paper is written from it.

| Date | Experiment / run | Data (n, institutions) | Hardware, time | Result (P/R/F1, coverage) | Where (commit, file) |
|---|---|---|---|---|---|
| November 1, 2026 (session 04) | OCR backlog of scanned UNZA PDFs, run 1 (`netd-mltext`, batches of 50 under `run.lock`) | 1,466 scans | server CPU, `nice 19`, about 18 s per PDF | **failed after 68 minutes with 15 PDFs OCRed**: `database is locked` when a manual `predict` (started outside `run.lock`) held the store longer than the 120 s busy timeout; the loop stopped on the first failed batch | `journalctl -u netd-mltext` |
| November 1, 2026 (session 04) | OCR backlog, run 2 (restarted 11:42 UTC; a failed batch no longer stops the loop; then `extract-text --retry-failed`) | 1,451 remaining scans | as above | 151 OCRed by 12:50 UTC; expected to finish about 19:00 UTC. Guarded apply and held-out evaluation to follow | `text-report` |
| November 1, 2026 (session 04) | Repository survey of the 30 HEA-listed institutions not harvested, plus 2 others: Chisale's (2024) ten DSpace repositories, host-name probing (`dspace.`, `repository.`, `ir.`, `elibrary.` … × 39 domains), institutions' library pages | 32 institutions | portal server, curl, about 1 hour | 9 repositories found: 5 reachable (Eden: OAI-PMH works, 1 non-thesis item in its ETD set; LAMU: OAI index corrupt, 2,727 malformed identifiers, GetRecord fails for 84/88, 2 MPH theses in its ETD collection; Mukuba, Kapasa Makasa, NIPA: no postgraduate theses, empty OAI indexes), 4 unreachable (CBU 502, Cavendish 403, Chalimbana and LMMU no answer). **No further institution harvestable**; harvestable on November 1, 2026: 4 of 34 (UNZA and UNILUS by OAI-PMH, ZCAS by REST and MU by METS fallbacks). Cf. Chisale (2024): 10 of 61 HEIs had repositories, 2 with OAI-PMH active | SRS §4 survey table, `harvester/institutions.yml` |
| November 1, 2026 | `titlepage-rules` v2 on first 171 UNZA texts (coverage only, no gold yet) | 171 UNZA | server CPU, about 3 s | coverage: degree level 64%, degree 63%, supervisor 36%, department 11%, faculty 16% | `titlepage.py` version 2 |
| November 1, 2026 | `openalex-fos` v1: OpenAlex Topics taxonomy (4 domains, 26 fields, 252 subfields; fetched November 1, 2026) and 27,511 OpenAlex works with English abstracts (≤ 120 per subfield, labelled by OpenAlex primary topic); `all-MiniLM-L6-v2` embeddings (title + first 1,000 characters of abstract) + multinomial logistic regression (C = 10); 85/15 stratified split | 23,384 train / 4,127 held-out OpenAlex works | workspace CPU, 2 threads: embedding 1,312 s (bge-small was ~15× slower and was dropped: about 3 vs 49 short texts/s) | held-out: subfield top-1 0.530, top-3 0.753; field 0.707; domain 0.852. Back-off (subfield ≥ 0.40, field ≥ 0.50): subfield for 63.3% (precision 0.686), field 15.5% (0.718), domain 21.2% (0.719). Version 2 (same weights, thresholds tuned on held-out works: subfield ≥ 0.30, field ≥ 0.40): subfield for 78% (precision 0.622), field 13% (0.630), domain only 10%; v1 on the portal gave subfield to only 48% of records (education theses split across related subfields). Not yet evaluated on portal records (needs annotation) | `harvester/tools/`, `netd/ml/models/data/openalex-fos-v1-report.md` |
| November 1, 2026 | `openalex-fos` v3: EM label-shift adaptation of subfield priors on the portal (Saerens et al. 2002) — **negative result, withdrawn** | 5,921 portal records (unlabelled) | server CPU, 211 s to embed | Education subfield 231 → 847 records, but Safety Research → 627 and Political Science → 923 (implausible): EM assumes pure label shift; theses vs journal papers is also concept shift, so confusions were amplified. v4 = v2 behaviour. Points to in-domain labels as the next step | `netd/ml/models/data/openalex-fos-v1-report.md` |
| November 1, 2026 | Gold standard: 2020 DataLab transcription of 3,267 UNZA ETDs (8 annotators; title, declaration, approval and acknowledgements pages); converted to `gold-unza-2020.csv`, split by hash of record id into dev 1,661 / test 1,606 | UNZA only | — | gold values: degree level 2,837, degree 2,814, supervisor 2,712, discipline 2,194, department 622. Caveat for the paper: 20 randomly drawn disagreements (from both halves) were inspected before the split was made | `work/`, `/opt/netd/logs/` |
| November 1, 2026 | `titlepage-rules` v9 on the **held-out test half** (threshold 0.8; recall counts records without text yet, OCR of scans still running) | 1,606 UNZA | server CPU | P / R / F1: degree level 0.991 / 0.478 / 0.645; degree 0.862 / 0.414 / 0.559; discipline 0.839 / 0.417 / 0.557; supervisor 0.797 / 0.234 / 0.362; department 0.963 / 0.243 / 0.388. Portal completeness after applying: supervisor 37.8% | `netd.cli evaluate` |
| November 1, 2026 | PDF text extraction backlog (text layer) | 5,925 records | server, 2 download threads, about 1 hour | text: UNZA 3,721, ZCAS 107, UNILUS 51, MU 11; scans: UNZA 1,455 (OCR ~18 s each on 2 shared CPUs); repository errors: UNZA 431, UNILUS 11 | `text-report` |
| November 1, 2026 | `titlepage-rules` v7 applied to the portal (threshold 0.8) | 3,905 texts | server CPU, about 8 minutes per full prediction run (before the word-count speed-up) | completeness, all sources: supervisor 0% → 34.7%, degree 17% → 62.3%, degree level 40% → 71.2%, department 0% → 4.7%; 3,366 records gained values; 2 records excluded as Bachelor's (both correct); 12/12 sampled new Doctoral labels correct; spot checks of 30 random values per version: about 27–28/30 correct at v4–v6 | `deploy/ops/netd-ml-apply.sh`, `/api/v1/stats` |
| November 1, 2026 | PDF text extraction backlog started | all records with PDFs | server, 2 threads, ~1.6 PDFs/s | about two-thirds of early UNZA PDFs are scans; ~15% of UNZA PDF links return HTTP 500 | `text-report` |

## Technical record from session 03 (November 1, 2026), for writing the paper

### System context
- Portal: Python harvester (OAI-PMH, DSpace REST fallback, CSV loader) → SQLite staging store (raw XML kept untouched; canonical ETD-MS-style records with per-field provenance and confidence) → Apache Solr 9.11 → Project Blacklight 9 on Rails 8 (UI modelled on Columbia's Academic Commons); own OAI-PMH provider (oai_dc, ETD-MS) and REST API; admin panel. One shared Ubuntu 20.04 server (2 vCPU, 3.8 GB RAM) hosted by ZAMREN; no GPU, no paid services.
- Collection on November 1, 2026: 5,923 postgraduate ETDs (UNZA 5,733, ZCAS 116, UNILUS 62, Mulungushi 12); 34 HEA-listed institutions, 30 with no harvestable ETDs.
- Architecture, pipeline, metadata-filling and field-of-study diagrams (reusable as paper figures): `blog-datalab26-netd_portal_implementation.zip` (SVG sources), generated by a script kept with it.

### Design decisions and rationale (metadata filling)
- **Models never write records.** Predictions go to a cache (record, field, model, version, value, confidence, evidence text, input hash); models rerun only when their input hash (PDF text hash + harvested values used + model version) changes. Models see harvested values only, never other models' output (no feedback loops).
- **Precedence:** manual correction > harvested value > prediction. A prediction fills only an empty field, only at confidence ≥ 0.8 (per-field override possible), and is marked "derived" (record page badge with model and confidence; API `derived` object).
- **Asymmetric risk for exclusion:** a predicted below-postgraduate degree level removes a record, so it is applied only at ≥ 0.95; 0.6–0.95 goes to a human review list; decisions are stored as corrections.
- **Front matter first:** some repositories split a thesis into "Cover page", "Preliminary pages" and "Main Document" files, and the first file is often the main document starting at Chapter 1; reading cover/preliminary files first was essential for UNZA.
- **Text:** first 8 pages per file (pypdf); scans (text layer < 80 characters) OCRed with Tesseract (first 5 pages, 200 dpi, greyscale, lowest CPU priority, about 18 s per PDF on the shared server).
- **Guarded application:** predict → dry run on a copy of the store → apply only if model-driven exclusions stay within a limit (10) (`deploy/ops/netd-ml-apply.sh`).

### Data observations
- UNZA: about 25% of PDFs are scans (1,455 of ~5,700), mostly pre-2015; about 7.5% of PDF links returned HTTP 500 from the repository at extraction time (431); 14 PDFs exceeded 60 MB. UNILUS links, internal-only earlier, mostly worked (51 of 62).
- PDF text extraction artefacts that rules must handle: words split by spaces ("M aster", "Zambi a", "Eco nomics"), hyphenated surnames with a stray space ("Chama -Chiliba"), names in all capitals, several supervisors on one line joined by commas, "and" or titles, and lines running into the next one (thesis title after a department name; "Word Count" or a copyright notice after a name or degree).
- Supervisor evidence locations seen: "Supervisor:" lines on approval/declaration pages, "supervised by", "under the supervision of", and acknowledgements ("my supervisor(s), Dr X and Prof Y"; "Dr X, my supervisor") — consistent with Nyambe et al. (in revision).

### Rules model development (`titlepage-rules`, versions 1–9, all November 1, 2026)
Iterated on real text with random spot checks of values and evidence (about 27–28/30 correct per check at v4–v6), then on the gold **dev** half only:
- v2: acknowledgement patterns for supervisors; corpus-frequency rejoining of split words (merge two fragments when the joined word is more frequent in the corpus than the rarer fragment).
- v3: units read line by line from title-page lines that start with "Department/School/Faculty of" (≤ 80 characters); case-sensitive degree abbreviations ("bed space" had matched B.Ed); surname of ≥ 4 letters required.
- v4–v6: stop words for run-ons; graduate-studies directorates not taken as faculties; long disciplines kept below the display threshold; several supervisors split at titles; institution names removed from disciplines.
- v7: every name on labelled supervisor lines; consistent capitalisation; per-record word counts no longer copy the corpus table (prediction ran ~8 minutes per full pass before).
- v8: degree name and discipline kept separate (ETD-MS `thesis.degree.name`), matching harvested degrees and keeping the Degree facet usable.
- v9: split surnames rejoined in the text before supervisor matching; hyphenated surnames.

### Evaluation method
- Gold standard: 2020 DataLab transcription of 3,267 UNZA ETDs (8 annotators; instructions https://drive.google.com/file/d/1BntQa5i4h2YPb7eKUJqG-F2BIIscUNRN/view; sheet https://docs.google.com/spreadsheets/d/1r1Ik5SPdxVnRUFN_dqBJ7gnK2YVnzJ3Kw8WYGVIh_3I); identifiers `oai:dspace.unza.zm:123456789/N` map to portal ids `unza-123456789-N`. "NULL" treated as not annotated.
- Split by SHA-256 of the record id (even → dev 1,661; odd → test 1,606). Caveat: 20 randomly drawn disagreements were inspected (from both halves) before the split was fixed; thereafter tuning used dev only.
- Matching (`netd/ml/evaluate.py`): Unicode folding, case, punctuation, titles (Dr, Prof, Mr …) and unit words removed; people compared by surname + first initial (handles "Phiri, Lighton" vs "Dr L. Phiri", glued titles such as "ProfessorY.Mulla", trailing commas); gold supervisor lists split on "||", "=", "and", "&"; degrees compared as degree names (discipline in parentheses or after "in" set aside; "Masters of" → "Master of").
- Annotator inconsistencies worth reporting: degree names sometimes include the discipline, sometimes not; "Masters of …"; supervisors with or without titles, joined by "and"; occasional typos ("r Prof.").
- Coverage and recall are reported over all gold records, including those without text yet (scans pending OCR, repository errors); precision is over displayed values.

### Fields of study (OpenAlex Topics) — model selection details
- Data: OpenAlex API now requires a free key; the workspace's anonymous daily budget was exhausted, the server's sufficed (~260 requests). Per subfield: `sample=120, seed=2026`, filter `primary_topic.subfield.id`, `has_abstract:true`, `language:en`; abstracts rebuilt from the inverted index; works with abstracts < 200 characters dropped → 27,511 works (`harvester/tools/openalex_training.py`). Labels are OpenAlex's own (machine-assigned) primary topics, so held-out accuracy is measured against noisy labels.
- Embedder choice: `BAAI/bge-small-en-v1.5` ran at about 3 texts/s on 2 CPUs (~200-word texts) vs about 49 texts/s for `all-MiniLM-L6-v2` (~120-word texts); bge-small would have taken hours for training and ~30 minutes per full portal pass, so MiniLM was chosen. Input: title + first 1,000 characters of abstract. Embedding 27,511 works: 1,312 s.
- A TF-IDF (1–2-grams, 200k features) + multinomial logistic regression baseline failed to train (needed ~9 GB for the optimiser) and was dropped.
- Classifier: multinomial logistic regression on normalised embeddings; C = 10 (top-1 0.530) beat C = 50 (0.498) and C = 200 (0.475).
- Threshold tuning table (held-out works) in `harvester/netd/ml/models/data/openalex-fos-v1-report.md`; chosen subfield ≥ 0.30, field ≥ 0.40 (version 2/4).
- On the portal (v1 thresholds 0.40/0.50) only 48% of records got a subfield (2,833 subfield, 1,560 field, 1,528 domain); School of Education theses: 1,061 subfield, 535 field, 213 domain, with confusions into Safety Research (102) and Human Factors and Ergonomics (58) — evidence of domain shift from journal papers to theses.
- EM label-shift adaptation (v3, negative result) and its counts: see the evidence log.
- Next: in-domain labels (discipline names and frequent repository headings mapped to subfields, an annotated portal sample), then retraining or calibration and evaluation on held-out portal records.

### Operational lessons (for a "deployment in a resource-constrained setting" section)
- SQLite in rollback-journal mode failed with "disk I/O error" when a read-only reader ran during long writes; WAL mode plus a busy timeout fixed it; in WAL, a read transaction left open cannot be upgraded to a write after another writer commits, so jobs read everything first, then write.
- Long jobs run as transient systemd units in batches under the harvest lock so the nightly harvest waits at most one batch.
- Rapid repeated SSH connections were briefly refused by the server; releases now use fewer connections.

### Artefacts and where they are
- Code: `harvester/netd/ml/` (text cache, cache, overlay, predict, evaluate, models), `harvester/tools/` (OpenAlex data, training, priors), `deploy/ops/netd-ml-apply.sh`; walkthrough notebook `notebooks/netd26-03-ml_metadata_filling-walkthrough.ipynb`.
- Data: gold files `gold-unza-2020*.csv` (laptop `work/`, server `/opt/netd/logs/`); OpenAlex training data `/opt/netd/harvester/models/openalex/` (taxonomy.json, works.jsonl); model weights and report `harvester/netd/ml/models/data/`.
- Requirements and design: SRS v0.26 (FR-14, FR-48 to FR-57, NFR-14, verification table), SDD v0.24 (§4.1.1).

## Technical record from session 04 (November 1, 2026), for writing the paper

### Institution onboarding: landscape findings
- The obstacles to national aggregation are mostly on the repository side, not in harvesting technology: OAI-PMH indexes that are never rebuilt after items are added or moved (ZCAS, LAMU, Mukuba, Kapasa Makasa, NIPA: DSpace's OAI index is separate from the repository and needs `dspace oai import`), repositories closed to outside visitors (Cavendish 403; Chalimbana and LMMU silent from the portal's network), broken installations (CBU: DSpace 7 front end 502, back end 404), and theses mixed with articles, books, teaching material and undergraduate projects (Mukuba, Kapasa Makasa, Eden).
- LAMU is an instructive failure: its OAI index lists 2,727 identifiers of the form `oai:oai:mydspace.org::123456789/N` (apparently an index from another installation), record headers carry the items' old collections, ListRecords fails with HTTP 500 in every format, and set queries return nothing. A well-formed identifier (`oai:localhost:123456789/248`) still works with GetRecord, so per-item access is possible once item handles are known from the JSPUI pages.
- Adaptive fallbacks already used (ZCAS: DSpace 7 REST; MU: DSpace 6 METS exports) show that aggregation can work around some repository faults, but at a per-institution engineering cost; for 2 theses (LAMU) the cost is not justified, and asking the institution to rebuild its index is the better route.
- Comparison over time for the paper: Chisale (2024) surveyed 61 HEIs: 10 had repositories, 2 had OAI-PMH active. On November 1, 2026: 34 HEA-listed postgraduate institutions; 4 harvestable (2 by OAI-PMH, 2 by fallbacks), 1 new repository with an (empty) ETD collection (Eden), 5 repositories unreachable or not harvestable.

### What was built
- Repository watch (SRS FR-58): `netd.cli check-repositories` probes every registry repository not yet harvested (page, OAI-PMH Identify, `ListIdentifiers` counts overall and in the ETD sets), keeps the result for the admin dashboard and the weekly email, and reports changes. Rationale: repositories appear, break and recover (Eden was set up the day before the survey; CBU was down on the day), so a one-off survey goes stale; the watch turns onboarding into an alert.
- Guide for institutions (FR-59): `https://netd.ac.zm/contribute`, written around the observed failure modes, plus the CSV route for institutions with no repository.

### Operational lessons
- Every job that writes the store must take `run.lock`, including one-off manual runs: the first OCR backlog run died after 68 minutes because a manual `predict` outside the lock held a write transaction past the 120 s busy timeout. Long loops now continue past a failed batch, and the next batch retries the same PDFs.
- `pkill -f`/`pgrep -f` over SSH match the remote shell's own command line; use a pattern such as `[o]aiprofile` so the shell does not kill itself.

## Evaluation
Field-level P/R/F1 (normalised matching; people by surname + initial); risk–coverage curves and calibration error; cross-institution generalisation (train UNZA, test ZCAS, MU, UNILUS); born-digital vs scanned; ablations (front matter first, page classification, grounding check, distillation); facet counts before and after (discoverability); cost, time and energy per 1,000 ETDs on free and CPU hardware.

## Venue
To be decided with Lighton when drafting (digital libraries or document-analysis venue).
