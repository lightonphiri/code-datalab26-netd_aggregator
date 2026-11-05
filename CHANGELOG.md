# Changelog

All notable changes to the Zambia National ETD Portal software (NETD v2). The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/).

**How the versions were made.** The project was built from October 30 to November 4, 2026 without release tags. On November 4, 2026 the real milestones were tagged retrospectively: each annotated tag points at the commit that completed the milestone, and the date given here is that commit's date. Commit dates were never changed. `paper-v1` is the version described in the research paper (frozen November 3, 2026) and is kept as it is. Requirement numbers (FR-, NFR-, EI-) refer to [docs/SRS.md](docs/SRS.md); the SRS and SDD revision histories give the detail of each change.

Every change after `paper-v1` is a post-paper change: it is not part of the results reported in the paper.

## [Unreleased]

Post-paper changes.

### Added
- Record page: "Similar theses" and "Cited by" start closed, with "+"/"−" on the right as on PubMed Central; a link to `#cited-by` opens that section (maintenance session 15).
- Filter lists at readable addresses (FR-71): the full list of one filter is at `/theses/filters/<name>` (e.g. `field-of-study`); Blacklight's `/catalog/facet/<field>` answers 301 (SRS 0.51, SDD 0.50; maintenance session 15).
- `robots.txt` and the REST API specification rendered from `config/country.yml` (packaging P6a; NFR-15): the sitemap address, portal name, addresses and contact come from the configuration; the files moved from `portal/public` to `portal/app/views/static_files/` (`robots.text.erb`, `openapi.text.erb`) and are served by the portal at the same addresses with the same content for Zambia. API specification changes are now made in `openapi.text.erb` (SRS 0.53, SDD 0.52).
- Site icons and credits in the theme (packaging P5b; NFR-15): `icon.png` and `icon.svg` moved from `portal/public` into the theme's `public/` (`zambia` keeps the same files; `default` has a neutral book icon); a theme may add `favicon.svg` or `favicon.ico` for the browser tab (`default` does; otherwise Blacklight's icon as before); a credit without a logo file is shown by its name on About and Credits instead of a broken image, and the footer then shows no logo. Zambian pages unchanged; manual 8.2 and 8.3 with screenshots of both themes (SRS 0.52, SDD 0.51).
- Theme folders (packaging P5a; NFR-15): `themes/<name>/` holds the colours and wordmark font (`stylesheets/theme.css`, imported after `netd.css`) and the logo files (`public/`, served at the same addresses); `portal.theme` in `config/country.yml` picks it. Shipped: `zambia` (today's look, pages and screenshots unchanged) and `default` (neutral colours). `netd.css` now reads every brand colour from the variables (SRS 0.50, SDD 0.49).
- Interface text in locale files, seventh and last part (packaging P4g; NFR-15): the admin dashboard, source, record correction, duplicates, quality, usage and report-form pages, the usage event labels (`netd.usage_events`) and every flash message (`netd.flash`, through `flash_text`) read their text from `en.yml`; admin dates through `I18n.l`. Every page's own text is now in `en.yml`; report contents, problem types and model validation messages stay in code (manual 8.6). Pages unchanged apart from white space (SRS 0.49, SDD 0.48).
- Interface text in locale files, sixth part (packaging P4f; NFR-15): the admin navigation and the sign-in, password, activity log, level review, problem report and CSV upload pages, admin times (`I18n.l`) and the problem-report mail read their text from `en.yml`; missing translations raise in development and test. Pages and mail unchanged apart from white space (SRS 0.48, SDD 0.47).
- Interface text in locale files, fifth part (packaging P4e; NFR-15): facet, record field, search field and sort labels are Blacklight's I18n keys in `en.yml` instead of `label:` values in `CatalogController`; institution status and quality group labels read from `en.yml` through `LocalisedLabels`; the Metadata Quality page's date through `I18n.l` with a `netd` format. Zambian pages unchanged (SRS 0.47, SDD 0.46).
- Interface text in locale files, fourth part (packaging P4d; NFR-15): the record page (including the Report a problem form and the "derived" notes), the search result cards and the Institution and Year facets' "more" and "fewer" toggles read their text from `en.yml`; copy, view and download counts use plural keys. Zambian pages unchanged apart from white space (SRS 0.46, SDD 0.45).
- Interface text in locale files, third part (packaging P4c; NFR-15): Browse by Faculty, Follow a search, Metadata Quality and the "Follow this search" button read their text from `en.yml`; the department count uses a plural key. Zambian pages unchanged apart from white space (SRS 0.45, SDD 0.44).
- Interface text in locale files, second part (packaging P4b; NFR-15): the text of About, Credits, FAQ, For Institutions, Developer Resources and the REST API reference is read from `en.yml`; the contact address, host name and portal address are available to every text as `%{email}`, `%{host}` and `%{base_url}`; the unread `credits.hosting` block was removed from `publications.yml`. Zambian pages unchanged apart from white space (SRS 0.44, SDD 0.43).
- Interface text in locale files, first part (packaging P4a; NFR-15): the header, footer and home-page wording is read from `portal/config/locales/en.yml` (keys under `netd.`) through the `nt` helper, with the portal, country and regulator names taken from `config/country.yml`; manual 8.6 explains how to change wording and add a language. Zambian pages unchanged apart from white space (SRS 0.43, SDD 0.42).
- Country configuration, second part (packaging P3b; NFR-15): country name and adjective, regulator (name, short name, web address), header wordmark, developer and host credits (header bar, footer, About, Credits, For Institutions) and the portal name in page titles, Blacklight's `application_name`, OAI-PMH `Identify`, RIS exports and problem-report e-mail now come from `config/country.yml`; installation words kept capitalised in citations from `citation.keep_capitals` (general list stays in `Citation::KEEP_GENERAL`). Zambian pages unchanged (SRS 0.41, SDD 0.40).
- Cited by, second part (FR-69): REST API 1.7.0 (`openalex_id`, `cited_by`, `cited` filter, `sort=cited`), OpenAlex identifier in OAI-PMH, "Cited" filter and "Most Cited" sort, "Cited by N" on result cards, citations in the HEA reports (SRS 0.39, SDD 0.38; maintenance track, 270194c).
- Country configuration, first part (packaging P3a; NFR-15): `config/country.yml` (Zambia as the example, also in `config/examples/zambia/`) read at start-up by the portal (`portal/config/netd_country.rb`), the harvester (`netd.config`) and the deployment scripts (`deploy/site.env`, written by `deploy.sh`); host name, contact and sender addresses, problem-report recipients, portal name in e-mail, reports and OAI-PMH, and the admin time zone now come from it. Pages and API responses are unchanged.
- Cited by (FR-69): theses matched to OpenAlex works by title and year (dissertations only); citing works listed on record pages, refreshed weekly (SRS 0.38, SDD 0.37; maintenance track).
- `CHANGELOG.md`, retrospective milestone tags `v0.1.0` to `v0.9.0`, the manual in `docs/manual/` (published with MkDocs on GitHub Pages) and `docs/PACKAGING-PLAN.md` (documentation and packaging track, from November 4, 2026).
- `LICENSE` (BSD 3-Clause), `NOTICE` (third-party material), `CONTRIBUTING.md`, `SECURITY.md`.

### Changed
- The SRS and SDD are published in the manual site under Reference (an MkDocs hook adds them at build time; the Markdown files stay the master copies); two SDD diagrams that GitHub could not render are fixed, and the diagrams no longer show the old `/beta` address.
- Manual chapters 5 and 10 describe Cited by (search, record page, REST API 1.7.0, OAI-PMH); new record-page screenshots.
- The site probe's recovery e-mail now says since when the portal was down (it read the outage start after deleting the file that held it).
- Record pages at `/theses/<short id>` (the DSpace default handle prefix dropped, e.g. `/theses/zcas-298`), with permanent redirects from `/catalog/<id>`; REST API 1.6.0 accepts the short id (FR-68, SRS 0.37, SDD 0.36; maintenance track).

### Fixed
- Cited by (FR-69): OpenAlex's temporary refusals (HTTP 429 with `Retry-After`) are waited out and logged as "rate-limited" instead of stopping the night's run as "daily budget"; a rejected API key no longer stops the job; the "Citations" filter list answers 404 instead of 500 (maintenance session 15).
- OpenAPI 1.7.0 description quoted (it did not parse); the API conformance test compares the export with every copy of a record (maintenance track, c91ea7f).
- OAI-PMH set `level:postgraduate-diploma` answered HTTP 500 (the two-word level was not quoted in the Solr filter); `tests/oai_conformance.py` now expects every record, duplicate copies included, as OAI-PMH lists them.

### Removed
- `portal/config/locales/blacklight.en.yml` (its only key, `application_name`, is now set from `portal.name` in `portal/config/locales/netd_country.rb`).
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
