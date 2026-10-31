# Software Design Description (SDD)
## Zambia National ETD Aggregator (NETD v2)

| Item | Value |
|---|---|
| Document | SDD, structured per IEEE 1016-2009 (design viewpoints) |
| Version | 0.16 |
| Date | October 31, 2026 |
| Owner | Dr Lighton Phiri, DataLab Research Group, University of Zambia |
| Related | `docs/SRS.md` (requirement IDs referenced below) |

### Revision history
| Version | Date | Changes |
|---|---|---|
| 0.1 | October 30, 2026 | Initial design: harvester, raw/canonical stores, crosswalk, enrichers, Blacklight portal, deployment |
| 0.2 | October 30, 2026 | Discipline/degree derivation; Solr analysers; URL-safe record ids; HTTPS |
| 0.16 | October 31, 2026 | `PagesController#faq/#developers/#credits`; footer partial; `credits` section in `publications.yml`; ZAMREN logo in `public/images/` |
| 0.10 | October 31, 2026 | Record page `catalog/show.html.erb` + `RecordHelper`; index gains `files_ssm` (name, type, size, URL per file) and `rights_ssm` |
| 0.9 | October 31, 2026 | `NetdHeaderComponent` (header), landing page redesign, new theme `netd.css` modelled on Academic Commons |
| 0.8 | October 31, 2026 | Served at the site root; Apache sites managed in `deploy/apache` (HTTP→HTTPS, redirects for `/beta` and old portal paths, `/znrp` and `/ojs` excluded); old Tomcat portal no longer proxied |
| 0.5 | October 31, 2026 | `bitstreams` table; file links from OAI `ore`, DSpace REST bundles and METS; `pdf_url`, `full_text_ssim` |
| 0.4 | October 31, 2026 | DSpace 6 METS loader (`netd.mets`); HTTPS proxy passes X-Forwarded-Proto (fixes record clicks) |
| 0.3 | October 31, 2026 | DSpace REST loader (`netd.rest`); institution registry, zero-count Institution facet and home page; About page from `publications.yml` |

---

## 1. Introduction
### 1.1 Purpose and scope
This SDD describes how NETD v2 meets the SRS: the system's context, components, information model, interfaces, interaction, state, deployment, and the main design decisions. It covers release 0.16.

### 1.2 Stakeholders and concerns
| Stakeholder | Concerns | Viewpoints |
|---|---|---|
| DataLab developers | Structure, extension points, deployment | Composition, Interface, Deployment |
| Data scientists | Where ML models plug in; provenance | Information, Interaction (§6.2) |
| Portal administrator | Operation, resource use, recovery | Deployment, State |
| Project lead / reviewers | Alignment with SA NETD and NDLTD; trade-offs | Context, Rationale |

---

## 2. Context viewpoint

### 2.1 Use cases
```mermaid
flowchart LR
  R((Researcher)):::actor
  A((Administrator)):::actor
  D((Data scientist)):::actor
  M((HEI repository<br/>manager)):::actor
  subgraph NETD v2
    UC1[Search ETDs]
    UC2[Filter by facets]
    UC3[View ETD record]
    UC4[Open full text in source IR]
    UC5[Register source]
    UC6[Run / schedule harvest]
    UC7[Re-process records]
    UC8[View completeness report]
    UC9[Register enricher / ML model]
  end
  R --- UC1 & UC2 & UC3 & UC4
  A --- UC5 & UC6 & UC7 & UC8
  D --- UC9 & UC7
  M --- UC8
  classDef actor fill:#fff,stroke:#333
```

### 2.2 System context
```mermaid
flowchart TB
  subgraph External
    IR1[UNZA RIMS OAI-PMH]
    IR2[UNILUS OAI-PMH]
    NDLTD[NDLTD Union Catalog]
    Users[Web users]
  end
  NETD[[NETD v2]]
  IR1 -->|ListRecords dim| NETD
  IR2 -->|ListRecords dim| NETD
  Users -->|HTTPS /beta| NETD
  NETD -.->|v0.3 OAI-PMH etdms| NDLTD
```

---

## 3. Composition viewpoint (components)

```mermaid
flowchart LR
  subgraph harvester ["harvester/ — Python 3.12"]
    CLI[netd.cli<br/>commands]
    HV[netd.harvest<br/>Sickle client]
    CW[netd.crosswalk<br/>dim/etdms/oai_dc → canonical]
    EN[netd.enrich<br/>rules + plug-in enrichers]
    IX[netd.index<br/>Solr JSON update]
    ST[netd.store<br/>SQLite]
  end
  ML[DataLab ML models<br/>package:function]
  DB[(netd.sqlite3)]
  SOLR[(Solr core 'netd')]
  subgraph portal ["portal/ — Rails 8 + Blacklight 9"]
    CC[CatalogController<br/>facets, fields, sorts]
    RC[EtdResultComponent<br/>cards, badges]
    TH[netd.css theme]
  end
  APA[Apache reverse proxy /beta]
  CLI --> HV --> ST
  CLI --> CW --> EN --> ST
  EN -.->|registered in enrichers.yml| ML
  CLI --> IX --> SOLR
  ST --- DB
  CC --> SOLR
  APA --> portal
```

| Component | Responsibility | SRS |
|---|---|---|
| `netd.harvest` | OAI-PMH client, format choice, sets, incremental runs, retries, run log | EI-1, FR-2–FR-8 |
| `netd.store` | Raw layer, set names, canonical layer, harvest runs | FR-7, FR-11 |
| `netd.crosswalk` | Flattening of `dim`/`etdms`/`oai_dc`; field mapping; set-based and text-based derivation; provenance | FR-12–FR-15 |
| `netd.enrich` | Built-in rules; loading and running external enrichers; confidence → facetable | FR-16–FR-18 |
| `netd.index` | Canonical → Solr document (Blacklight dynamic-field names) | FR-21 |
| `netd.rest` | Fallback loader: DSpace 7 REST API items → `dim` XML in the raw layer (set specs from collection and parent community) | FR-10 |
| file links (all loaders) | OAI-PMH sources: second `ListRecords` pass in `ore`, taking `ore:aggregates` links (DSpace 7 UI download links normalised to `/server/api/core/bitstreams/<uuid>/content` on the repository host); REST: item ORIGINAL bundle; METS: CONTENT file group. Stored in table `bitstreams`; crosswalk sets `pdf_url` (largest PDF first) or `file_url` | FR-32 |
| `netd.mets` | Fallback loader: DSpace 6 XMLUI collection browse pages → item handles → `/metadata/handle/<h>/mets.xml` → embedded `dim` stored in the raw layer | FR-10 |
| `netd.cli` | `harvest`, `process`, `index`, `run`, `report` | FR-9, FR-27 |
| `institutions.yml` + `InstitutionRegistry` | All HEA-accredited postgraduate HEIs with harvest status | FR-29 |
| `InstitutionFacetComponent` | Institution facet listing registry institutions with no records as 0 (hidden once an institution is selected) | FR-29 |
| `NetdHeaderComponent` | Group bar, wordmark, search box, link row (About, Explore, Master's, PhD) | EI-5 |
| Home page (`catalog/_home_text`) | Intro line; Explore Master's/PhD cards; stats at a glance; contributing institutions with the HEA list behind a toggle | FR-26, FR-30, FR-33 |
| `PagesController#about` + `publications.yml` | Project details and publications; `deploy/gen_publications_md.py` writes `PUBLICATIONS.md` from the same file | FR-31 |
| Blacklight portal | Search UI, facets, sorting, record pages, JSON API | FR-20–FR-24, EI-3, EI-5 |
| Solr core `netd` | Blacklight schema (ICU analysers replaced by built-in ASCII folding, as the slim Solr distribution lacks the ICU module); `qf` tuned to ETD fields | NFR-1 |

---

## 4. Information viewpoint

### 4.1 Persistent data (SQLite)
```mermaid
erDiagram
  RAW_RECORDS {
    text source PK
    text oai_id PK
    text datestamp
    text set_specs "JSON list"
    int deleted
    text metadata_prefix
    text xml "untouched payload"
    real harvested_at
  }
  SET_NAMES {
    text source PK
    text set_spec PK
    text set_name
  }
  RECORDS {
    text id PK "source-handle, e.g. unza-123456789-9143"
    text source
    text data "canonical JSON"
    real updated_at
  }
  HARVEST_RUNS {
    int id PK
    text source
    real started_at
    real finished_at
    text from_date
    int records
    int deleted
    text status
    text message
  }
  RAW_RECORDS ||--o| RECORDS : "processed into"
  SET_NAMES ||--o{ RAW_RECORDS : "names setSpecs of"
  HARVEST_RUNS }o--|| RAW_RECORDS : "writes"
```

### 4.2 Canonical record (class view)
```mermaid
classDiagram
  class Source {
    +id: str
    +name: str
    +short_name: str
    +base_url: str
    +formats: list
    +sets: list
    +ignore_set_names: list
    +collections_are: faculty or department
  }
  class CanonicalRecord {
    +id: str
    +institution: str
    +title: list
    +author: list
    +supervisor: list
    +subject: list
    +faculty: list
    +department: list
    +degree: list
    +degree_level: list
    +year: list
    +abstract: list
    +url: list
    +provenance: dict
    +confidence: dict
    +facetable: dict
  }
  class Enricher {
    <<interface>>
    +__call__(record) record
  }
  class TitleCase
  class PersonNames
  class MLModel {
    model:name-version
  }
  Source "1" --> "*" CanonicalRecord
  Enricher <|.. TitleCase
  Enricher <|.. PersonNames
  Enricher <|.. MLModel
  Enricher ..> CanonicalRecord : modifies + records provenance
```

### 4.3 Field mapping (crosswalk)
| Canonical | `dim` source fields (priority order) | Fallbacks |
|---|---|---|
| title | `dc.title` | — |
| author | `dc.contributor.author`, `dc.creator` | — |
| supervisor | `dc.contributor.advisor`, `.supervisor`, `.promoter` | ML/PDF (planned) |
| subject | `dc.subject`, `.other`, `.lcsh`, `.ddc` | — |
| faculty | `thesis.degree.faculty`, local fields | set hierarchy (`collections_are`, "School/Faculty of …") |
| department | `thesis.degree.department`, local fields | set hierarchy; "Department of …" pattern in descriptions |
| degree, discipline | `thesis.degree.name`, `thesis.degree.discipline` | "Master of X in Y" / "PhD Y" patterns in `dc.description` |
| degree_level | `thesis.degree.level` | patterns over degree, type, description and set names |
| year | `dc.date.issued` | first 4-digit year |
| url | `dc.identifier.uri` | — |

### 4.4 Solr document
`id, title_tsim/ssm/ssort, author_tsim/ssim, supervisor_tsim/ssim, subject_tsim/ssim, faculty_tsim/ssim, department_tsim/ssim, faculty_department_ssim ("Faculty|Dept"), discipline_tsim/ssim, degree_ssim, degree_level_ssim, year_isi/ssim, abstract_tesim, url_ssm, institution_ssim, institution_short_ssim, provenance_ssm, completeness_isi`. A facet (`*_ssim`) value is omitted when its field is not `facetable` (FR-17).

---

## 5. Interface viewpoint
| Interface | Description |
|---|---|
| CLI | `python -m netd.cli {harvest|process|index|run|report} [--source ID] [--full] [--limit N] [--db PATH] [--solr URL]`; env `NETD_DB`, `NETD_SOLR`, `NETD_SOURCES`, `NETD_ENRICHERS` |
| Enricher contract | `def enrich(record: dict) -> dict`; set `record["provenance"][field] = "model:<name>-<version>"` and optionally `record["confidence"][field] = float` |
| Solr | JSON `POST /solr/netd/update`; Blacklight queries `/select` (edismax, ETD `qf`) |
| HTTP | `GET /beta/` (search), `/beta/catalog/<id>` (record), `/beta/catalog.json?q=…` (JSON) |

---

## 6. Interaction viewpoint

### 6.1 Scheduled harvest and indexing
```mermaid
sequenceDiagram
  autonumber
  participant T as systemd timer
  participant C as netd.cli run
  participant H as harvest
  participant IR as HEI OAI-PMH
  participant S as store (SQLite)
  participant X as crosswalk+enrich
  participant Q as Solr
  T->>C: daily 02:30
  loop each source
    C->>H: harvest_source(src)
    H->>IR: ListMetadataFormats / ListSets
    H->>S: put_set_names
    H->>IR: ListRecords(prefix, set, from)
    IR-->>H: records + resumptionToken (repeat)
    H->>S: put_raw(...) untouched XML
    H->>S: log_run(status)
  end
  C->>X: to_canonical + enrichers (from raw)
  X->>S: put_record(canonical + provenance)
  C->>Q: POST /update (batches of 500), deletes, commit
```

### 6.2 Plugging in an ML model
```mermaid
sequenceDiagram
  participant DS as Data scientist
  participant Y as enrichers.yml
  participant C as netd.cli process
  participant M as model function
  DS->>Y: add "datalab_models.supervisors:extract"
  DS->>C: netd process && netd index
  C->>M: record
  M-->>C: record (+provenance "model:…", confidence)
  Note over C: below min_confidence → searchable, not faceted
```

### 6.3 Search
```mermaid
sequenceDiagram
  participant B as Browser
  participant A as Apache /beta
  participant P as Puma + Blacklight
  participant Q as Solr
  B->>A: GET /beta/?q=malaria&f[faculty_ssim][]=Medicine
  A->>P: proxy 127.0.0.1:3010
  P->>Q: /select edismax + facet.field…
  Q-->>P: docs + facet counts
  P-->>B: HTML (cards, facets)
```

---

## 7. State dynamics viewpoint (harvest run)
```mermaid
stateDiagram-v2
  [*] --> Discovering: ListMetadataFormats/ListSets
  Discovering --> Harvesting: format chosen
  Harvesting --> Harvesting: resumptionToken
  Harvesting --> Retrying: HTTP 5xx
  Retrying --> Harvesting: after Retry-After
  Retrying --> Failed: retries exhausted
  Harvesting --> Completed: no token / NoRecordsMatch
  Completed --> [*]: status=ok (sets next from=)
  Failed --> [*]: status=error (next run repeats window)
```

---

## 8. Deployment viewpoint
```mermaid
flowchart TB
  subgraph server ["Server portal — netd.ac.zm — Ubuntu 20.04, 2 vCPU, 3.8 GiB + 2 GiB swap"]
    AP[Apache 2.4 :80/:443<br/>netd.ac.zm: / → Puma; HTTP → HTTPS]
    TC["Tomcat :8080<br/>other applications; old portal no longer proxied"]
    PU[netd-portal.service<br/>Puma 127.0.0.1:3010, 1 worker]
    SO[netd-solr.service<br/>Solr 9.11 127.0.0.1:8983, 512 MB heap]
    TI[netd-harvest.timer<br/>daily harvest+process+index]
    FS["/opt/netd: harvester, portal, solr, ruby, netd.sqlite3"]
  end
  AP --> PU
  PU --> SO
  TI --> SO
```
- All NETD services run as the unprivileged user `netd` (NFR-5) and are installed under `/opt/netd`.
- No Docker and no apt changes (C1). Python comes via `uv`; Ruby is compiled with `ruby-build`.
- Apache sites for netd.ac.zm live in `deploy/apache/` and are installed by `deploy.sh`, which backs up the previous files in `/opt/netd/`. Rollback: restore those backups and restart Apache.
- The earlier ETD Portal (Tomcat :8080) is no longer proxied; Tomcat keeps running because it hosts other applications.

---

## 9. Design rationale
| Decision | Alternatives considered | Reason |
|---|---|---|
| Custom Python pipeline + Blacklight | InvenioRDM; VuFind; DSpace as aggregator | ML models are Python; the raw store makes cleaning re-runnable; InvenioRDM's harvester module is experimental and its "harvest always wins" policy overwrites cleaning; the server's RAM (3.8 GiB, shared) rules out an Invenio stack |
| SQLite (v0.1) | PostgreSQL | Zero extra memory or daemon; adequate for ≤ 100k records; can migrate later |
| `dim` before `etdms`/`oai_dc` | `oai_dc` only | Retains qualified DSpace fields (advisor, local fields) |
| Set hierarchy for Faculty | Manual mapping only | UNZA RIMS ETD collections are Schools; derivable with provenance `set:` |
| Provenance and confidence on every value | Overwrite in place | Lets the team measure each model's contribution; low-confidence values don't pollute facets |
| Sub-path `/beta` | New sub-domain | No DNS change needed (constraint C3) |
| Native systemd services | Docker | Lower memory overhead on a shared 4 GB server |

## 10. Known limitations (v0.8)
- Supervisor and Department are empty for all harvested sources: the IRs don't expose them. ML/PDF extraction is deferred until the portal is complete.
- 30 of the 34 HEA-listed institutions show 0 (no reachable ETD repository).
- HTTPS for netd.ac.zm is in place (NFR-9); HTTP redirects to HTTPS since v0.8.
- The old portal's OAI-PMH endpoint (/OAI-PMH) is retired with it; NETD v2's own OAI-PMH provider (EI-4) is not built yet.
- No OAI-PMH provider yet (EI-4); no deduplication (FR-19).
