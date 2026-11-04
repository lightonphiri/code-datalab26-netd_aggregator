# Changelog

All notable changes to the Zambia National ETD Portal software (NETD v2). The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/).

**How the versions were made.** The project was built from October 30 to November 4, 2026 without release tags. On November 4, 2026 the real milestones were tagged retrospectively: each annotated tag points at the commit that completed the milestone, and the date given here is that commit's date. Commit dates were never changed. `paper-v1` is the version described in the research paper (frozen November 3, 2026) and is kept as it is. Requirement numbers (FR-, NFR-, EI-) refer to [docs/SRS.md](docs/SRS.md); the SRS and SDD revision histories give the detail of each change.

Every change after `paper-v1` is a post-paper change: it is not part of the results reported in the paper.

## [Unreleased]

Post-paper changes.

### Added
- Cited by (FR-69): theses matched to OpenAlex works by title and year (dissertations only); citing works listed on record pages, refreshed weekly (SRS 0.38, SDD 0.37; maintenance track).
- `CHANGELOG.md`, retrospective milestone tags `v0.1.0` to `v0.9.0`, the manual in `docs/manual/` (published with MkDocs on GitHub Pages) and `docs/PACKAGING-PLAN.md` (documentation and packaging track, from November 4, 2026).
- `LICENSE` (BSD 3-Clause), `NOTICE` (third-party material), `CONTRIBUTING.md`, `SECURITY.md`.

### Changed
- Record pages at `/theses/<short id>` (the DSpace default handle prefix dropped, e.g. `/theses/zcas-298`), with permanent redirects from `/catalog/<id>`; REST API 1.6.0 accepts the short id (FR-68, SRS 0.37, SDD 0.36; maintenance track).

### Removed
- A Python bytecode cache that had been committed by mistake (`deploy/ops/__pycache__/`); `.gitignore` now covers every `__pycache__` folder and the manual's build output.

## [v0.9.0] – November 4, 2026 (commit ae15b79) – post-paper

How to cite, discoverability by Google Scholar, and similar theses (SRS 0.34–0.36, SDD 0.33–0.35).

### Added
- How to cite on record pages (FR-65): the same ten CSL styles as OJS (APA by default), copy button, RIS and BibTeX downloads.
- Google Scholar and Google (FR-66): Highwire Press meta tags, Open Graph, canonical links and `/sitemap.xml`; Google Search Console verification.
- Similar theses (FR-67): five per record page from Solr MoreLikeThis, in a collapsible section that is open by default.
- Search results without repository keywords show the portal's field of study (FR-55).
- Icons for view and download counts on record pages and on `/admin/usage` (FR-61).

### Changed
- Repository links are rebuilt from OAI identifiers on every harvest (UNZA links pointed to a host no longer in DNS); the record page label is now "Repository link".
- Titles written in capitals are put into sentence case in citations.

## [paper-v1] – November 3, 2026 (commit fe6f8c7)

The version described in the paper. Backups moved to the project's own Google OAuth client; the inventory for the handover to HEA added to `docs/OPERATIONS.md` (SDD 0.32). No evaluated component changed after `v0.8.0`.

## [v0.8.0] – November 2, 2026 (commit a8e9959)

Supervisor names and a read-only role for HEA (SRS 0.33, SDD 0.31).

### Added
- Supervisor name variants (FR-64): one name per person within an institution, display only; original spellings kept and shown on the record page.
- Account roles (FR-36): admin, and a read-only viewer role for HEA staff (reports, metadata quality and usage only).

### Changed
- Crawler filter for usage counts extended to scanners and user agents without a platform (FR-61).

## [v0.7.0] – November 2, 2026 (commit 8943475)

Reports for HEA (SRS 0.32, SDD 0.30).

### Added
- Reports (FR-63): per institution, by supervisor, and custom reports (filters, grouping by one or two fields, chosen columns), as Excel and PDF, for signed-in administrators, with optional usage figures.

### Changed
- OCR backlog finished; final apply and the FINAL evaluation on scanned (OCRed) theses recorded (FR-48, FR-50, FR-52, FR-53).

## [v0.6.0] – November 2, 2026 (commit cbee2ea)

Metadata filling v11 and the born-digital evaluation (SRS 0.31, SDD 0.29).

### Added
- Usage analytics by country and approximate city (offline DB-IP Lite lookup, no address stored), facet values chosen, and view and download counts on record pages (FR-61).
- Gold-sample tooling for several sources, with duplicate copies left out and dev/test halves.

### Changed
- `titlepage-rules` v10 and v11 (supervisor statements in many forms, name rejoining, unit names); evaluator fixes (title lookahead, person matching on surname and initials). FINAL born-digital evaluation recorded.
- 39 more undergraduate dissertations excluded after hand checks (FR-52).

## [v0.5.0] – November 2, 2026 (commit 4718fb8)

Usage analytics and department names (SRS 0.30, SDD 0.28).

### Added
- Usage analytics (FR-61): server-side daily counts of searches, record views, PDF downloads, browsing, API and OAI-PMH requests; no third-party trackers, IP addresses or search words kept; `/admin/usage` with CSV.
- Department name variants merged per institution at index time (FR-62).

### Changed
- No search history for crawlers; `robots.txt` disallows facet combinations, feeds and data formats; search history kept for one day.
- UNZA Library collection kept as its own unit (a separate entity, not a School).

## [v0.4.0] – November 2, 2026 (commit 3d1a3b5)

Duplicates and browsing (SRS 0.28–0.29, SDD 0.26–0.27).

### Added
- Duplicate theses (FR-19): matched by DOI or near-identical title with compatible authors and years; listed once under a main record; copies linked; admin decisions; API 1.5.0.
- Browse by faculty and department (FR-25) at `/browse`.
- Evaluation by kind of PDF text (`evaluate --strata`, FR-53); guarded apply that counts only new model exclusions.

### Changed
- Server upgraded from Ubuntu 20.04 to 26.04.1 LTS; Ruby 3.3.6 rebuilt against OpenSSL 3.5; harvester environment recreated with uv (Python 3.12); upgrade scripts in `deploy/ops/upgrade/`.
- An unreachable repository is recorded as a failed run and no longer stops the other sources.

## [v0.3.0] – November 1, 2026 (commit 41ad6e5)

Metadata filling, fields of study and institution onboarding (SRS 0.25–0.27, SDD 0.23–0.25).

### Added
- Metadata filling (FR-14, FR-48 to FR-53): PDF text cache with OCR for scanned PDFs (Tesseract), prediction cache, `titlepage-rules` model (v2 to v9), derived values marked on the portal and in the API (API 1.1.0), manual corrections, degree-level review and exclusion, gold-standard evaluation; walkthrough notebook.
- Standard fields of study from OpenAlex Topics (FR-54 to FR-57): `openalex-fos` model, Research domain, Field of study and Subfield facets, API 1.2.0.
- Institution onboarding: weekly check of repositories not yet harvested (FR-58), guide for institutions (FR-59), API 1.3.0.
- Public metadata quality dashboard against ETD-MS 1.1 (FR-28); per-institution detail in the admin panel.
- Follow new additions (FR-60): date added, Newest Additions sort, Atom and RSS feeds for any search, API 1.4.0.

### Changed
- Staging store in SQLite WAL mode with a busy timeout.

## [v0.2.0] – November 1, 2026 (commit fa6a086)

Interfaces and administration (SRS 0.20–0.24, SDD 0.18–0.22).

### Added
- OAI-PMH 2.0 data provider at `/oai` (EI-4): all six verbs, `oai_dc` and ETD-MS v1.1, institution and degree-level sets.
- CSV loader for institutions without a working repository (FR-10), with a public template.
- Admin panel at `/admin` (FR-36 to FR-41): dashboard and harvest on demand, problem reports, CSV upload with checking, activity log.
- REST API v1 at `/api/v1` (EI-6, FR-42 to FR-46) with an OpenAPI 3 specification.
- Postgraduate scope (FR-47): records below postgraduate level are excluded; Postgraduate Diploma recognised.

## [v0.1.0] – October 31, 2026 (commit a6d8756)

First public portal (SRS 0.1–0.19, SDD to 0.17).

### Added
- Harvester: UNZA and UNILUS over OAI-PMH, ZCAS University over the DSpace 7 REST API, Mulungushi University from DSpace 6 METS exports; cleaning pipeline with a plug-in point for models; Solr indexing.
- Blacklight 9 portal served at https://netd.ac.zm/ (replacing the earlier UCT ETD Portal deployment), modelled on Columbia's Academic Commons: landing page, facets, sort, record pages, direct PDF links, problem reports, About, FAQ, Developer Resources and Credits pages.
- All HEA-accredited postgraduate institutions listed, with zero counts where not harvested.
- Operations: nightly backups to the server and Google Drive, failure alerts, site probe, weekly status, harvest health check.

[Unreleased]: https://github.com/lightonphiri/code-datalab26-netd_aggregator/compare/v0.9.0...HEAD
[v0.9.0]: https://github.com/lightonphiri/code-datalab26-netd_aggregator/compare/paper-v1...v0.9.0
[paper-v1]: https://github.com/lightonphiri/code-datalab26-netd_aggregator/compare/v0.8.0...paper-v1
[v0.8.0]: https://github.com/lightonphiri/code-datalab26-netd_aggregator/compare/v0.7.0...v0.8.0
[v0.7.0]: https://github.com/lightonphiri/code-datalab26-netd_aggregator/compare/v0.6.0...v0.7.0
[v0.6.0]: https://github.com/lightonphiri/code-datalab26-netd_aggregator/compare/v0.5.0...v0.6.0
[v0.5.0]: https://github.com/lightonphiri/code-datalab26-netd_aggregator/compare/v0.4.0...v0.5.0
[v0.4.0]: https://github.com/lightonphiri/code-datalab26-netd_aggregator/compare/v0.3.0...v0.4.0
[v0.3.0]: https://github.com/lightonphiri/code-datalab26-netd_aggregator/compare/v0.2.0...v0.3.0
[v0.2.0]: https://github.com/lightonphiri/code-datalab26-netd_aggregator/compare/v0.1.0...v0.2.0
[v0.1.0]: https://github.com/lightonphiri/code-datalab26-netd_aggregator/releases/tag/v0.1.0
