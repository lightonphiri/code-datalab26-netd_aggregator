# Software Requirements Specification (SRS)
## Zambia National ETD Aggregator (NETD v2) — Harvesting, Cleaning and Discovery Service

| Item | Value |
|---|---|
| Document | SRS, structured per ISO/IEC/IEEE 29148:2018 (supersedes IEEE 830-1998) |
| Version | 0.15 |
| Date | October 31, 2026 |
| Owner | Dr Lighton Phiri, DataLab Research Group, University of Zambia |
| Repository | https://github.com/lightonphiri/code-datalab26-netd_aggregator |
| Status | Draft for review |

### Revision history
| Version | Date | Changes |
|---|---|---|
| 0.1 | October 30, 2026 | Initial SRS: harvesting (UNZA, UNILUS), cleaning pipeline, Blacklight discovery |
| 0.2 | October 30, 2026 | Discipline and Degree fields (FR-12, FR-21); institution entry points (FR-26); HTTPS (NFR-9); PDF pilot and onboarding findings (§4) |
| 0.15 | October 31, 2026 | FR-34: Report a problem popup form (stored and emailed) replaces the email link |
| 0.14 | October 31, 2026 | FR-24: Report a problem email link and Analysis panel (Google Scholar link) on record pages |
| 0.13 | October 31, 2026 | EI-5: header link row limited to About and Explore |
| 0.12 | October 31, 2026 | FR-22: "Sort by" menu as on Academic Commons — Best Match, Published Latest, Published Earliest, Title A-Z, Title Z-A |
| 0.11 | October 31, 2026 | FR-31: About page lists project members with their DataLab roles and only publications based on the Zambia National ETD Portal project, with an explanatory paragraph |
| 0.10 | October 31, 2026 | FR-24: record page modelled on Academic Commons — subject tags, Files panel, More About This Work panel, download/persistent-link panel |
| 0.9 | October 31, 2026 | Interface modelled on Columbia's Academic Commons [R15]: new header and theme (EI-5); landing page with stats at a glance and Master's/PhD explore cards (FR-33) |
| 0.8 | October 31, 2026 | Portal moved to the site root, https://netd.ac.zm/, replacing the earlier ETD Portal; HTTP redirects to HTTPS; /beta and old portal addresses redirect (EI-2, C3, §1.2) |
| 0.7 | October 31, 2026 | FR-21: Year facet lists newest years first, 5 visible with a "more »" toggle |
| 0.6 | October 31, 2026 | FR-29: Institution facet shows the top 10 rows with a "more »" toggle for the rest |
| 0.5 | October 31, 2026 | Direct links to full-text files (FR-32): PDF link on result cards and record pages, Full text facet |
| 0.4 | October 31, 2026 | Mulungushi University harvested via DSpace 6 METS exports (FR-10); EI-2 clarified for HTTPS form posts |
| 0.3 | October 31, 2026 | HEA institution registry with zero counts (FR-29, FR-30); About page with publications (FR-31); ZCAS via DSpace REST fallback (FR-10); ML/PDF extraction deferred until the portal is complete (FR-14); new sources [R12]–[R14] |

---

## 1. Introduction

### 1.1 Purpose
This document specifies the requirements for a national Electronic Theses and Dissertations (ETD) aggregation service for Zambia. The service harvests ETD metadata from Higher Education Institution (HEI) institutional repositories (IRs) using OAI-PMH, cleans and enriches it, and offers faceted discovery by Title, Author, Subject, Supervisor, Faculty and Department. It is intended for the DataLab project team, HEI repository managers, and reviewers such as the Higher Education Authority (HEA).

### 1.2 Scope
The system ("NETD v2") replaces, in stages, the current Zambia National ETD Portal at https://netd.ac.zm, which runs the UCT ETD Portal software [R4] and holds about 5,269 UNZA records [R1]. Since October 31, 2026 (v0.8) it is served at `https://netd.ac.zm/`, replacing the earlier portal, and covers:
- harvesting from three HEIs (UNZA RIMS and UNILUS over OAI-PMH; ZCAS University over the DSpace REST API), and listing all HEA-accredited postgraduate institutions [R12], [R13];
- a cleaning pipeline with a plug-in point for DataLab's machine-learning (ML) models;
- a Blacklight 9 discovery interface over Apache Solr.

Out of scope: depositing ETDs, user accounts and hosting full texts. (Replacing the earlier portal was completed in v0.8.)

### 1.3 Definitions, acronyms and abbreviations
| Term | Meaning |
|---|---|
| ETD | Electronic Thesis or Dissertation |
| HEI | Higher Education Institution |
| IR | Institutional Repository (e.g. DSpace) |
| OAI-PMH | Open Archives Initiative Protocol for Metadata Harvesting, v2.0 |
| `oai_dc`, `dim`, `etdms` | OAI-PMH metadata formats: unqualified Dublin Core; DSpace Intermediate Metadata; ETD-MS |
| ETD-MS | NDLTD's interoperability metadata standard for ETDs (v1.1) |
| Raw store | Unmodified harvested metadata, kept so cleaning can be re-run |
| Canonical record | Cleaned ETD record with per-field provenance |
| Provenance | The origin of a field value: harvested, derived from sets, extracted from text, or produced by a model |
| Enricher | A cleaning/enrichment function, rule-based or ML, run on canonical records |

### 1.4 References
- [R1] Chileshe, E. & Phiri, L. (2024). *Zambia National ETD Portal: Implementation of an Interoperable National Electronic Thesis and Dissertation Portal.* ETD 2024 poster. https://docs.google.com/presentation/d/18grbYjU2LdcqHDs4V-cququXvMyJCenFykFJUq8xnBc/edit
- [R2] *Quality of Metadata in the Zambia National ETD Portal* (abstract). https://docs.google.com/document/d/1HKeNgRV_AzEjIGdtOKItG0TGanwYF43voNgMNtibj_g/edit
- [R3] *Design and Implementation of an Interoperable Zambia National Electronic Thesis and Dissertation Portal* (ETD 2024 abstract). https://docs.google.com/document/d/1RgbfrHOBhbt5Y1aHFGt0bXS5SZjJ8lUtLVD-mU3t-vM/edit
- [R4] Webley, L., Chipeperekwa, T. & Suleman, H. (2011). *Creating a National Electronic Thesis and Dissertation Portal in South Africa.* ETD 2011. Project page: https://dl.cs.uct.ac.za/projects/etd_portal.html
- [R5] Chanda, Kanfwa & Mainda (2023). *Zambia National ETD Pre-Processing Pipeline.* https://datalab.unza.zm/sites/default/files/2023-12/reports-unza23-ict4014-chanda_kanfwa_mainda.pdf
- [R6] Chisale, A. (2024). *Identification of Sources for Missing Electronic Theses and Dissertations Metadata in Higher Education in Zambia.* MLIS dissertation, University of Zambia. https://datalab.unza.zm/sites/default/files/2024-06/etds-datalab24-mlis-dissertation-adrian_chisale.pdf
- [R7] NDLTD (2021). *ETD-MS v1.1.* https://ndltd.org/wp-content/uploads/2021/04/etd-ms-v1.1.html
- [R8] Open Archives Initiative. *OAI-PMH v2.0.* https://www.openarchives.org/OAI/openarchivesprotocol.html
- [R9] NDLTD Union Catalog. https://ndltdunion.cs.uct.ac.za/portal/
- [R10] Project Blacklight. https://projectblacklight.org/
- [R11] ISO/IEC/IEEE 29148:2018 *Systems and software engineering — Life cycle processes — Requirements engineering.*

### 1.5 Overview
Section 2 describes the product context and constraints. Section 3 lists verifiable requirements. Section 4 gives verification methods and traceability.

---

## 2. Overall description

### 2.1 Product perspective
NETD v2 follows the SA NETD multi-tier model [R4]: *Harvester → Repository (store) → Portal*. It adds a **cleaning tier** with provenance between harvesting and indexing, motivated by the metadata-quality findings in [R2], [R5] and [R6]. Downstream, it will in turn expose an OAI-PMH provider so that NDLTD [R9] can harvest Zambia as a single source (planned for v0.3).

```mermaid
flowchart LR
  subgraph HEIs
    A[UNZA RIMS<br/>DSpace 7+] ; B[UNILUS<br/>DSpace 7+] ; C[Other HEI IRs]
  end
  A & B & C -- OAI-PMH --> H[Harvester]
  H --> R[(Raw store)]
  R --> P[Crosswalk + Enrichers<br/>rules & ML models]
  P --> K[(Canonical records<br/>with provenance)]
  K --> S[(Solr index)]
  S --> U[Blacklight portal<br/>netd.ac.zm/beta]
  K -.->|v0.3| O[OAI-PMH provider] -.-> N[NDLTD Union Catalog]
```

### 2.2 Product functions (summary)
1. Register and onboard HEI repositories (source registry).
2. Harvest ETD metadata selectively (by set) and incrementally.
3. Keep raw metadata unchanged, and process it into canonical records.
4. Clean and enrich fields with rules and pluggable ML models, recording provenance.
5. Index records and offer search, faceting, sorting and record pages.
6. Report field completeness per institution.

### 2.3 User classes and characteristics
| User class | Description | Main needs |
|---|---|---|
| Researcher / student (public) | Searches for ETDs nationally | Fast search; facets by institution, faculty, department, supervisor, subject, year; link to full text |
| HEI repository manager | Librarian responsible for an IR | Confirm their ETDs are harvested; see completeness gaps |
| Portal administrator (DataLab) | Runs the service | Add sources, schedule harvests, re-run cleaning, monitor |
| Data scientist (DataLab) | Builds cleaning/ML models | Plug models in without changing platform code; compare model versions |
| Oversight body (HEA) | Reviews national ETD output | Aggregate counts and quality indicators |

### 2.4 Operating environment
- Server `portal` (netd.ac.zm): Ubuntu 20.04.6 LTS, 2 vCPU, 3.8 GiB RAM, 2 GiB swap file, 162 GB free disk. It is shared with other live services: Apache (80/443), Tomcat (current portal, :8080), Orthanc, MySQL and nginx.
- No Docker. Python 3.12 (standalone, via `uv`), Ruby 3.3 (`ruby-build`), OpenJDK 11, Solr 9.11 (slim), SQLite.
- Browsers: current Chrome, Firefox, Edge and Safari, including mobile.

### 2.5 Design and implementation constraints
- C1 Must not disturb the live portal or other services on the server, and must not change system packages (apt is currently in a broken state).
- C2 Memory budget: Solr heap ≤ 512 MB; web app ≤ 300 MB resident.
- C3 Must not depend on actions by third parties (e.g. DNS changes). The `/beta` sub-path was used while both portals ran (October 30–31, 2026); retired in v0.8.
- C4 Open-source components only; source code versioned on GitHub.
- C5 ML models are Python; the cleaning tier must be Python.
- C6 British English in the interface and documentation.

### 2.6 Assumptions and dependencies
- A1 HEI repositories expose OAI-PMH. Verified on October 30, 2026 for UNZA RIMS (`https://rims.unza.ac.zm/server/oai/request`) and UNILUS (`https://research.unilus.ac.zm/server/oai/request`). Both offer `dim`, `etdms`, `oai_dc` and others.
- A2 Supervisor and department are **not** present in the harvested metadata of either sample source (0% completeness, measured on October 30, 2026). They will require text/PDF extraction or ML (FR-14).
- A3 Full texts remain in the source IRs; NETD stores links only.

---

## 3. Specific requirements

Priority: **M** = must (v0.1), **S** = should (v0.2), **C** = could (later).

### 3.1 External interface requirements
| ID | Requirement | Pri |
|---|---|---|
| EI-1 | The harvester shall act as an OAI-PMH 2.0 client supporting `Identify`, `ListMetadataFormats`, `ListSets` and `ListRecords`, with resumption tokens. | M |
| EI-2 | The portal shall be served over HTTPS at the root of netd.ac.zm through the existing Apache server (reverse proxy), with HTTP redirected to HTTPS and the former `/beta/` and old ETD Portal addresses (`/portal`, `/summary`, `/harvester`) redirected; the HTTPS proxy shall pass `X-Forwarded-Proto: https` so that form posts pass Rails' origin check. | M |
| EI-3 | The portal shall offer a JSON view of search results and records (Blacklight `.json`). | S |
| EI-4 | The system shall expose an OAI-PMH data provider (`oai_dc`, `etdms`) of canonical records. | C |
| EI-5 | The UI shall follow the style of Columbia's Academic Commons [R15]: system UI typography, a navy group bar, a serif wordmark with the search box, a link row (About, Explore), white pages with light cards, one blue for links and actions; facet sidebar and result list with badges on search pages. | M |

### 3.2 Functional requirements

**Source management and harvesting**
| ID | Requirement | Pri |
|---|---|---|
| FR-1 | Sources shall be configured in a registry file (`harvester/sources.yml`) giving id, name, short name, base URL, preferred metadata formats, ETD sets, and set-name rules. | M |
| FR-2 | For each source, the harvester shall choose the first preferred format the source offers (default order `dim`, `etdms`, `oai_dc`). | M |
| FR-3 | The harvester shall restrict harvesting to the configured ETD sets. | M |
| FR-4 | The harvester shall support full and incremental (`from=` last successful run minus one day) harvests. | M |
| FR-5 | The harvester shall record OAI deletions and remove deleted records from the index. | M |
| FR-6 | The harvester shall retry on HTTP 500/502/503/504 and honour `Retry-After`. | M |
| FR-7 | Each harvest run shall be logged (source, start/end, from-date, counts, status, message). | M |
| FR-8 | The harvester shall store the set hierarchy (`ListSets`) for each source. | M |
| FR-9 | Harvests shall run on a schedule (daily) without manual action. | S |
| FR-10 | Fallback adapters shall be available for HEIs without working OAI-PMH: DSpace 7 REST API (v0.3, used for ZCAS); DSpace 6 XMLUI browse pages + per-item METS exports (v0.4, used for Mulungushi); CSV upload (later). | S |

**Processing, cleaning and enrichment**
| ID | Requirement | Pri |
|---|---|---|
| FR-11 | Raw metadata shall be stored unmodified; processing shall be re-runnable from the raw store without re-harvesting. | M |
| FR-12 | A crosswalk shall map `dim`, `etdms` and `oai_dc` to canonical fields: title, author, supervisor, subject, faculty, department, discipline, degree, degree level, year, abstract, URL, language, type, institution. | M |
| FR-13 | Faculty/Department shall be derived from the set hierarchy where a source's collections represent units (per-source rule `collections_are`). | M |
| FR-14 | Supervisor, Department and Degree shall be extracted from free-text fields (v0.2) and, later, from PDF front matter with OCR/ML. PDF/ML work is **deferred until the portal is complete** (decision of October 31, 2026). | S (text) / C (PDF, deferred) |
| FR-15 | Every canonical field value shall carry provenance (`harvested:`, `set:`, `text:`, `rule:`, `model:`). | M |
| FR-16 | Enrichers shall be pluggable as Python callables `f(record) -> record`, registered in `enrichers.yml` without code changes to the platform. | M |
| FR-17 | Enrichers may set a confidence per field. Values below `min_confidence` shall stay searchable but shall not be used as facet values. | M |
| FR-18 | Built-in rules shall normalise whitespace, ALL-CAPS titles (keeping the original), personal names, and ALL-CAPS unit names. | M |
| FR-19 | Duplicate ETDs across sources shall be detected (identifier, then title+author+year). | C |

**Discovery**
| ID | Requirement | Pri |
|---|---|---|
| FR-20 | Users shall search by keyword across all fields, or within Title, Author, Supervisor or Subject. | M |
| FR-21 | Users shall filter by facets: Institution, Degree level, Faculty/School, Department, Programme/Discipline, Degree, Supervisor, Subject, Year (newest first; the 5 latest years visible, the rest behind "more »"). | M |
| FR-22 | Users shall sort results from a "Sort by" menu beside the result count, as on Academic Commons [R15]: Best Match (default), Published Latest, Published Earliest, Title A-Z, Title Z-A. | M |
| FR-23 | Result cards shall show degree-level, year and institution badges, title, author, supervisor (when present), and an abstract snippet. | M |
| FR-24 | Record pages shall follow the Academic Commons record layout [R15]: year/type/degree-level kicker, title, authors, abstract; Subjects and Programme/Discipline as tag buttons linking to searches; a Files panel (name, type, size, download per file); all other metadata (institution, faculty, department, thesis advisors, degree, degree level, year, language, source record) in a "More About This Work" panel; and a top-right panel with Download, persistent link with copy, sharing links, rights and holding institution, a "Report a problem" button opening the form in FR-34, and an Analysis panel linking to the work on Google Scholar, where its "Cited by" count is shown. Google Scholar has no public API, so the count itself is not shown on the portal. | M |
| FR-25 | Hierarchical Faculty → Department browsing. | S |
| FR-26 | Institution entry points (InvenioRDM "communities" equivalent): the home page lists each institution with its ETD count. Implemented in v0.2. | S |

**Reporting**
| ID | Requirement | Pri |
|---|---|---|
| FR-27 | The administrator shall obtain a per-institution field-completeness report from the command line. | M |
| FR-28 | A public quality dashboard (completeness and ETD-MS compliance per HEI). | C |

**Coverage and project information**
| ID | Requirement | Pri |
|---|---|---|
| FR-29 | An institution registry (`harvester/institutions.yml`) shall list every HEI with at least one HEA-accredited Master's or Doctoral programme [R12], [R13]. The home page and the Institution facet shall show every registry institution (the facet shows the top 10 rows, harvested institutions first, with a "more »" toggle for the rest), with **0** where nothing is harvested and the reason (no repository known, no ETD collection, repository not reachable). | M |
| FR-30 | The home page shall state that metadata is meant to be harvested from all institutions offering HEA-accredited Master's and PhD programmes, citing HEA. | M |
| FR-31 | The portal (About page) and the repository (`PUBLICATIONS.md`) shall list the project details [R14], the project members with their roles as on the DataLab people page (the PI marked Principal Investigator), and the publications, dissertations and capstone reports based on the Zambia National ETD Portal project, with a short explanation of how they relate to the portal, from one source file (`portal/config/publications.yml`). | M |
| FR-34 | Record pages shall offer a "Report a problem" popup form (problem type, message, name, email address, record URL). Each report shall be stored in the portal database and emailed to lighton.phiri@unza.ac.zm and datalab@unza.zm (subject "(Zambia National ETD Portal) <problem>: <title>", reply-to the reporter) through an authenticated SMTP account; the form shall have a spam trap and a rate limit. | M |
| FR-33 | The landing page shall show a one-line introduction, two prominent buttons — Explore Master's Manuscripts and Explore PhD Manuscripts (degree-level filtered searches) — "stats at a glance" (total ETDs, master's, doctoral, with full-text PDF, institutions contributing of those listed, years covered) and the contributing institutions, with the not-yet-harvested HEA institutions behind a toggle. | M |
| FR-32 | For every ETD whose repository exposes it, the portal shall link directly to the full-text file (bitstream), preferring the largest PDF, on result cards and record pages, and offer a Full text facet (PDF available / other file / metadata only). Files stay in the source repositories. | M |

### 3.3 Non-functional requirements
| ID | Category | Requirement | Pri |
|---|---|---|---|
| NFR-1 | Performance | Search result pages shall render in ≤ 1.5 s (server time, p95) for 10,000 records. | M |
| NFR-2 | Capacity | v0.1 shall handle ≥ 50,000 records within constraint C2. | M |
| NFR-3 | Resource | Total added resident memory ≤ 1 GB under normal load. | M |
| NFR-4 | Availability | Services shall restart automatically (systemd) after failure or reboot. | M |
| NFR-5 | Isolation | Services run as unprivileged user `netd`; Solr binds to 127.0.0.1 only. | M |
| NFR-6 | Maintainability | Adding a new DSpace source shall need only a registry entry. | M |
| NFR-7 | Portability | Installation scripted (`deploy/install-server.sh`, `deploy/deploy.sh`). | M |
| NFR-8 | Usability | Responsive layout; WCAG 2.1 AA colour contrast for badges and links. | S |
| NFR-9 | Security | HTTPS for netd.ac.zm with a valid certificate (in place since October 30, 2026; Let's Encrypt, auto-renewing). | S |
| NFR-10 | Politeness | At most one concurrent request per source. | M |

### 3.4 Data requirements
The canonical record is a JSON object stored in SQLite (`records.data`):
`id, source, institution, institution_short, oai_id, datestamp, title[], author[], supervisor[], subject[], faculty[], department[], degree[], degree_level[], year[], abstract[], url[], language[], type[], provenance{field: origin}, confidence{field: 0..1}, facetable{field: bool}, raw_fields[]`.

---

## 4. Verification

| Requirement(s) | Method | v0.1 evidence |
|---|---|---|
| EI-1, FR-2–FR-8 | Test: full harvest of both sources | October 30, 2026: UNZA 6,287 headers (37 deleted) and UNILUS 77 (15 deleted), both via `dim`, status ok |
| FR-11–FR-13, FR-15, FR-18 | Test: `netd process`; inspect provenance | 5,798 canonical records; UNZA Faculty 100% from sets |
| FR-27 | Demonstration: `netd report` | Completeness table (below) |
| FR-20–FR-24, EI-2, EI-5 | Demonstration in browser at `/beta/` | Screenshots in release notes |
| NFR-1, NFR-3 | Measurement (`curl -w`, `ps`) | Recorded at deployment |
| NFR-4, NFR-5 | Inspection of systemd units | `deploy/systemd/*.service` |

Completeness (October 31, 2026, v0.3):

| Institution | Records | Title | Author | Supervisor | Subject | Faculty | Department | Discipline | Degree | Degree level | Year |
|---|---|---|---|---|---|---|---|---|---|---|---|
| UNILUS | 62 | 100% | 100% | 0% | 85% | 0% | 0% | 0% | 0% | 100% | 100% |
| UNZA | 5,736 | 100% | 100% | 0% | 84% | 100% | 0% | 16% | 18% | 40% | 100% |
| MU | 12 | 100% | 100% | 0% | 100% | 0% | 0% | 0% | 0% | 0% | 100% |
| ZCASU | 116 | 99% | 98% | 0% | 49% | 100% | 0% | 0% | 0% | 0% | 99% |

Direct PDF links (October 31, 2026, v0.5): UNZA 98%, UNILUS 100%, ZCASU 97%, MU 92% of records; every sampled link returned the PDF itself.

Institution registry (October 31, 2026): 34 HEIs have HEA-accredited postgraduate programmes, taken from HEA's accredited-programmes data and checked against [R12] (text) — [R13] is a scanned PDF and could not be machine-read. 4 are harvested (Mulungushi University since v0.4: OAI-PMH and REST are switched off on its DSpace 6.3, so its Theses and Dissertations collection is read from per-item METS exports); Mukuba University's repository has no ETD collection; 29 have no known public repository. Kapasa Makasa University and NIPA repositories were checked but have no ETD collection and no HEA-accredited postgraduate programme. ZCAS's OAI-PMH endpoint answers but returns no records for any set, so its items are read from the DSpace 7 REST API (FR-10).

PDF pilot (October 30, 2026): the OAI-PMH `ore` format exposes each ETD's PDF link. Of 12 randomly sampled UNZA PDFs (0.2–16 MB; 2 links returned HTTP 500), 4 had no extractable text (scanned images), and no supervisor name was found by rules in the first six pages; 1 yielded a department. Supervisor/Department extraction therefore needs OCR and ML, not rules — the intended use of FR-14/FR-16. UNILUS PDF links point to an internal address (`41.63.7.239:4000`) that the portal cannot reach.

These gaps (Supervisor, Department, UNZA degree level) are the targets for the DataLab ML enrichers (FR-14, FR-16).

### 4.1 Traceability to sources
| Need (source) | Requirements |
|---|---|
| Central national access to ETDs [R3] | FR-1–FR-9, FR-20–FR-24 |
| Metadata quality and standardisation [R2], [R5] | FR-11–FR-18 |
| ETD-MS compliance gaps; elements in different places per HEI [R6] | FR-12–FR-14, FR-28 |
| SA NETD tiered architecture [R4] | §2.1 |
| Feed NDLTD [R9] | EI-4 |
| Faceting by Supervisor/Faculty/Department (project brief) | FR-21, FR-25 |
| National coverage of HEA-accredited postgraduate institutions [R12], [R13] | FR-29, FR-30 |
| Project visibility and publications [R14] | FR-31 |
