# 10. Interfaces

NETD offers its collection to programs through four interfaces. All of them read the Solr index only, so they show what the nightly index holds and never touch the staging store. Examples use the Zambian installation, https://netd.ac.zm.

## 10.1 REST API v1

Base address `/api/v1`. Read-only JSON, no authentication, CORS open. The contract is `portal/public/api/v1/openapi.yaml` (OpenAPI 3.0.3), rendered with an interactive reference at `/developers/api`.

| Endpoint | What |
|---|---|
| `GET /api/v1/records` | search: `q`, filters (institution, degree level, year range, field of study, `cited=true` or `false`, and more), `sort` (`relevance`, `newest`, `cited` and others), `page`, `per_page` (up to 10,000 results in all) |
| `GET /api/v1/records/{id}` | one record (full id, or the short id of its page address) |
| `GET /api/v1/institutions` | every institution expected, with record counts, harvest status and last run |
| `GET /api/v1/stats` | counts by institution, level and year, and completeness per field (cached 10 minutes) |
| `GET /api/v1/export.csv`, `/api/v1/export.jsonl` | the whole collection (rebuilt when more than 6 hours old) |

```bash
curl -s 'https://netd.ac.zm/api/v1/records?q=malaria&per_page=5' | python3 -m json.tool
```

Each record has stable public field names (`title`, `authors`, `supervisors`, `degree`, `degree_level`, `institution {id, name}`, `fields_of_study`, `links {portal, source, pdf, api}`, `files`, `duplicate_of`, `other_copies`, `openalex_id`, `cited_by {count, works}`, `updated_at`) and a `derived` list naming every value the portal filled in, with its method and confidence. Lists are always arrays; missing single values are `null`. `cited_by.count` is `null` when the thesis has not been matched in OpenAlex (not yet checked, or no confident match) and 0 when it was matched and nobody cites it; each citing work has `openalex_id`, `title`, `year`, `type` and `url`. The CSV export ends with the columns `openalex_id` and `cited_by_count` (API 1.7.0).

**Limits:** 120 requests a minute per address, 20 an hour for the export. Errors: 400 with a message for bad parameters, 404, 503 when the index is unavailable.

**Versioning:** within v1, fields are only added, never renamed or removed (the minor version in the specification records each addition). An incompatible change would be `/api/v2`, with v1 kept for at least 6 months.

## 10.2 OAI-PMH data provider

Base address `/oai` (OAI-PMH 2.0), for aggregators such as NDLTD's Global ETD Search.

| Aspect | Value |
|---|---|
| Verbs | all six, GET or POST |
| Formats | `oai_dc`; `etdms` (ETD-MS v1.1, supervisors as `contributor role="advisor"`, `degree` with name, level, discipline and grantor) |
| Sets | `inst:<source id>` per institution; `level:masters`, `level:doctoral`, `level:postgraduate-diploma` |
| Identifiers | `oai:<host>:<record id>`; in the records, `dc:identifier` (oai_dc) and `identifier` (ETD-MS) list the portal page, the repository page, the PDF and, when matched, the thesis in OpenAlex (`https://openalex.org/W…`) |
| Datestamps | when the record's content last changed in the portal (seconds granularity), so incremental harvesting only returns real changes |
| Paging | 100 records per page; stateless resumption tokens valid 24 hours |
| Deleted records | `transient` |

```bash
curl -s 'https://netd.ac.zm/oai?verb=ListRecords&metadataPrefix=etdms&set=level:doctoral'
```

`tests/oai_conformance.py` validates an installation against the OAI-PMH and Dublin Core schemas and exercises every verb and error.

## 10.3 Sitemap and search engine tags

`/sitemap.xml` lists every record page (rebuilt from Solr, cached one day). Record pages carry Highwire Press `citation_*` meta tags (title, authors, date, institution as dissertation institution, PDF link), Open Graph tags and a canonical link, which is what Google Scholar reads. See [chapter 7](07-configuration.md), 7.9.

## 10.4 Feeds

`/follow` with any search's parameters gives Atom and RSS feeds of new additions matching that search, dated by the day each thesis was added to the portal. The search results page links to them ("Follow this search"). Crawlers are asked not to fetch feeds (`robots.txt`).

## 10.5 Other

- Blacklight's own JSON view of search pages (`/catalog.json?q=...`) follows the website and may change; use the REST API instead.
- `/up` returns HTTP 200 when the portal is running (for uptime monitors).
- The CSV template for institutions is at `/netd-etd-template.csv`.
