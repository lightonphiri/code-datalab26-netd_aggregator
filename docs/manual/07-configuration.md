# 7. Configuration reference

Every file an installation may need to change, with its settings. Paths are relative to `/opt/netd` (the repository root). After changing a harvester file, run `reprocess` (or the step named); after changing a portal or deployment file, run `deploy/deploy.sh`.

## 7.1 `config/country.yml` — the installation's identity

One file names the country, the portal and the people behind it. The portal, the harvester and the deployment scripts read it at start-up; a missing file, a missing required key or an unknown time zone stops them with a message that names the file and the key. Start from an example: `cp config/examples/zambia/country.yml config/country.yml`, then edit it and run `deploy/deploy.sh`. To keep the file elsewhere, set `NETD_COUNTRY` to its path (in `portal.env` and the systemd units).

```yaml
country:
  name: Zambia
  adjective: Zambian
  time_zone: Africa/Lusaka          # IANA name
portal:
  name: Zambia National ETD Portal
  wordmark: [Zambia, National ETD Portal]
  host: netd.ac.zm                  # public host name, served over HTTPS
regulator:
  name: Higher Education Authority
  short_name: HEA
  url: https://www.hea.org.zm
  register_url: https://online.hea.org.zm
contact:
  email: datalab@unza.zm
  reports_to: [lighton.phiri@unza.ac.zm, datalab@unza.zm]
mail:
  from: datalab@unza.zm
  sender: lighton.phiri@unza.ac.zm
credits:
  - {name: DataLab Research Group, url: https://datalab.unza.zm, logo: datalab-logo-light.svg, logo_height: 40,
     class: datalab-credit, article: the, role: developed by}
  - {name: ZAMREN, full_name: Zambia Research and Education Network, url: https://zamren.zm, logo: zamren-logo.png,
     logo_height: 48, class: zamren-credit, role: hosted by}
citation:
  keep_capitals: [Zambia, Zambian, Zambians, Lusaka, Copperbelt, Luapula, Muchinga, Ndola, Kitwe, Kabwe, Livingstone,
                  Chipata, Kasama, Solwezi, Mongu, Mansa, Chongwe, UNZA, ZESCO, ZRA, ZNBC]
locale: en
```

| Key | Required | Used for |
|---|---|---|
| `country.name`, `country.adjective` | yes | page text ("theses from Zambian universities") |
| `country.time_zone` | yes | times in the admin panel and on the quality pages, and their label ("Lusaka time") |
| `portal.name` | yes | browser titles, the home, FAQ, About and Credits pages, e-mail, report headers and document properties, OAI-PMH `Identify`, RIS exports |
| `portal.wordmark` | yes | the two parts of the header wordmark (exactly two) |
| `portal.theme` | no | the theme folder in `themes/` (colours, wordmark font, logo files; [chapter 8.3](08-customisation.md)); `default` when absent |
| `portal.host` | yes | every absolute address: OAI-PMH base URL and identifiers (`oai:<host>:<record id>`), REST API links, links in e-mail, Developer Resources examples, harvester user agents, the site probe and alerts |
| `regulator.name`, `regulator.short_name`, `regulator.url` | yes | the body that accredits the institutions: named and linked on the home, FAQ and For Institutions pages; the short name in admin pages, reports and the API's institution list ("HEA-listed"); `register_url` (optional) is its online register |
| `contact.email` | yes | the public address on the pages and in OAI-PMH `Identify` |
| `contact.reports_to` | yes | recipients of "Report a problem" |
| `mail.from` | yes | default sender of portal e-mail |
| `mail.sender` | yes | sender of problem reports when `SMTP_FROM` and `SMTP_USER` are not set in `portal.env` |
| `credits` | no | developer and host credits, in order: header bar (role `developed by`), footer sentence and logo, About and Credits pages (role `hosted by` is the server's host). Each entry needs `name`, `url`, `role`; optional `full_name`, `logo` (file in `portal/public/images/`), `logo_height`, `class` (style class of the logo link), `article` ("the") |
| `citation.keep_capitals` | no | your country's place names, institutions and bodies kept capitalised when a title in capitals is put into sentence case (added to a general list) |
| `locale` | no | interface language (default `en`) |

`deploy.sh` writes the values the shell scripts need to `deploy/site.env` (do not edit it; it is rewritten on every deployment). To see them: `sudo -u netd env PYTHONPATH=/opt/netd/harvester /opt/netd/harvester/.venv/bin/python -m netd.config --env`.

Changing `portal.host` changes the OAI-PMH identifiers of every record: harvesters of your portal will see new records. Choose the host before the portal is announced.

## 7.2 `harvester/sources.yml` — sources harvested

```yaml
scope:
  degree_levels: [Doctoral, Masters, Postgraduate Diploma]   # records identified as another level are excluded

sources:
  - id: unza                       # short, lower case; used in record ids and on the command line
    name: University of Zambia     # exactly as in institutions.yml
    short_name: UNZA               # shown in results and reports
    base_url: https://rims.unza.ac.zm/server/oai/request
    formats: [dim, etdms, oai_dc]  # first one the repository offers is used
    sets: [com_123456789_18]       # OAI-PMH setSpecs holding theses
    collections_are: faculty       # repository collections name faculties (or: department)
    ignore_set_names: ["Theses and Dissertations"]   # container collections that are not units
    set_units:                     # collections that are not units: {faculty: ..., department: ...}, null for none
      col_123456789_5183: {faculty: null}
    exclude_records:               # single records left out, with the reason
      - {oai_id: "oai:rims.unza.ac.zm:123456789/8053", reason: "Bachelor of Laws dissertation"}
```

| Key | Required | Meaning |
|---|---|---|
| `id`, `name`, `short_name` | yes | identity of the source |
| `base_url` | OAI-PMH sources | the OAI-PMH endpoint |
| `formats` | no | metadata formats in order of preference (default `[dim, etdms, oai_dc]`) |
| `sets` | no | restrict harvesting to these sets (strongly advised: repositories hold more than theses) |
| `loader` | no | `dspace7-rest` (with `rest_api`, `collections`), `dspace6-mets` (with `xmlui`, `collections`) or `csv` (with `csv_path` or `csv_url`); omitted for OAI-PMH |
| `collections_are` | no | `faculty` or `department`: map repository collection names to that unit |
| `ignore_set_names` | no | collection names never used as units |
| `set_units` | no | per-collection override of faculty and department |
| `exclude_records` | no | records left out, each with `oai_id` and `reason` |
| `record_url` | no | `harvested` keeps the repository's own record links; by default links are rebuilt from the OAI identifier as `https://<host>/handle/<handle>` |
| `files` | no | `false` skips the second pass that collects direct PDF links |

`harvester/sources.local.yml` (not in the repository) holds sources added from the admin panel, in the same format.

## 7.3 `harvester/institutions.yml` — institutions expected

```yaml
institutions:
  - {name: University of Zambia, levels: [Masters, PhD], status: harvested, source: unza}
  - {name: Cavendish University, levels: [Masters, PhD], status: repository-unreachable,
     repository: "https://dspace.cavendishza.org/", oai: "...", etd_sets: [...], checked: "2026-11-01",
     note: "every path answers 403 Forbidden to outside visitors"}
```

`status` is one of `harvested`, `no-etds-yet`, `no-etd-collection`, `repository-unreachable`, `no-repository-known`. `oai` and `etd_sets` are probed weekly by `check-repositories`. In Zambia the list is every institution with an accredited Master's or Doctoral programme (from the Higher Education Authority's register); another country would use its own regulator's register.

## 7.4 `harvester/enrichers.yml` — cleaning and metadata filling

| Setting | Default | Meaning |
|---|---|---|
| `enrichers` | `[]` | extra `package.module:function` enrichers run after the built-in rules |
| `min_confidence` | 0.6 | values below this are searchable but not faceted |
| `ml.show_threshold` | 0.8 | predicted values below this are not shown |
| `ml.thresholds.<field>` | — | per-field override (`field_of_study: 0.0`: the model backs off to field or domain itself) |
| `ml.level_auto_exclude` | 0.95 | a predicted below-postgraduate level at or above this excludes the record |
| `ml.level_review_min` | 0.6 | between this and `level_auto_exclude`: queued for review |
| `ml.nightly` | true | the nightly run extracts text, OCRs and predicts for new or changed records |
| `ml.nightly_pdfs`, `ml.nightly_ocr` | 300, 30 | nightly limits per source (PDFs) and overall (OCR) |

## 7.5 `/opt/netd/portal.env` — secrets and mail (not in the repository; mode 600)

| Variable | Meaning |
|---|---|
| `SECRET_KEY_BASE` | Rails secret; generated by `deploy.sh` |
| `SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD` | sending account for problem reports and alerts |
| `SMTP_FROM` | sender address, if not `SMTP_USER` |
| `ALERT_TO` | recipients of alerts and the weekly status (default `SMTP_USER`) |
| `RAILS_FORCE_SSL` | `true` to have Rails itself force HTTPS (normally Apache does this) |
| `OPENALEX_API_KEY` | optional: the nightly Cited by job (without a key OpenAlex allows about 100 calls a day, with a free key ten times as many; on a native install the key goes in `/opt/netd/openalex.env`, read by systemd) and rebuilding the fields-of-study model. A key OpenAlex rejects is logged and the job runs without it |

`SOLR_URL` is set in the systemd unit, not here.

## 7.6 systemd units — `deploy/systemd/`

| Unit | Notes |
|---|---|
| `netd-solr.service` | Solr on 127.0.0.1:8983, 512 MB heap |
| `netd-portal.service` | Puma on 127.0.0.1:3010; sets `SOLR_URL`, `RAILS_ENV`, `RAILS_MAX_THREADS=3`, `WEB_CONCURRENCY=0`; reads `portal.env` |
| `netd-harvest.service` / `.timer` | daily `run` under `run.lock`, then `check` |
| `netd-backup.service` / `.timer` | nightly backup and off-server copy; prunes search history |
| `netd-probe.service` / `.timer` | public site check every 15 minutes (address from `deploy/site.env`) |
| `netd-weekly.service` / `.timer` | repository check and weekly status |
| `netd-alert@.service` | sends the alert for a failed unit |

Times in the timers are server time (UTC on the Zambian server).

## 7.7 Apache — `deploy/apache/`

`netd.conf` (port 80: redirect to HTTPS, Let's Encrypt webroot) and `netd-le-ssl.conf` (port 443: TLS, `RequestHeader set X-Forwarded-Proto "https"`, proxy `/` to `http://127.0.0.1:3010/`). Paths excluded from the proxy (`ProxyPass /path !`) are other applications on the same host. On a shared server, give it a **catch-all default site** so that unknown host names do not show another site's content.

## 7.8 Solr — `solr/netd/conf`

The Blacklight schema with ASCII folding instead of ICU analysers (the slim Solr distribution has no ICU module), ETD search fields and their weights (`qf`, `pf` per search field in `solrconfig.xml`), spelling dictionaries, and the MoreLikeThis component used for similar theses. `deploy.sh` copies it into the core and reloads the core.

## 7.9 Portal

| File | Setting |
|---|---|
| `portal/config/blacklight.yml` | Solr URL from `SOLR_URL` |
| `portal/app/controllers/catalog_controller.rb` | facets, search fields, sort options, results per page |
| `portal/config/publications.yml` | publications shown on the About page (and written to `PUBLICATIONS.md` by `deploy/gen_publications_md.py`) |
| `portal/config/csl/` | citation styles and the locale file (see [chapter 8](08-customisation.md)) |
| `portal/app/views/static_files/robots.text.erb` | crawler rules (facet combinations, feeds and data formats disallowed); served at `/robots.txt` with the sitemap address from `portal.host` |
| `portal/app/views/static_files/openapi.text.erb` | the REST API specification, served at `/api/v1/openapi.yaml` with the names and addresses from `config/country.yml` |
| `portal/public/netd-etd-template.csv` | the CSV template for institutions |

## 7.10 Search engines

The sitemap is at `/sitemap.xml` (built from Solr, cached one day) and is named in `robots.txt`. Record pages carry Highwire Press `citation_*` meta tags (read by Google Scholar), Open Graph tags and a canonical link. To register with Google Search Console, verify the property with an HTML file in `portal/public/` (keep the file, or verification is lost) and submit the sitemap. Google Scholar has no submission form; it finds records through the sitemap within weeks to months.

## 7.11 Settings still in code

These are planned to move into `config/country.yml` or templates rendered from it (`docs/PACKAGING-PLAN.md`):

| What | Where now |
|---|---|
| Administrator address and host name in the Apache sites | `deploy/apache/` |
| Host name in the upgrade check and the backup destination | `deploy/ops/upgrade/upgrade-check.sh`, `deploy/ops/netd-backup-to-gdrive.sh` |
| Words that are never names (title-page rules) | `harvester/netd/ml/models/titlepage.py` |
