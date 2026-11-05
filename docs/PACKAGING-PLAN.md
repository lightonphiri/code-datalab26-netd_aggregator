# Packaging plan: NETD as open-source software for other countries

Started November 4, 2026 (documentation and packaging track, session 13). Goal (Lighton, November 4, 2026): release the software under an open-source licence so that another country can install it and make basic customisations. All the work below is **post-paper**: it changes no evaluated component and no figure reported for `paper-v1`.

## 1. Decisions

| Decision | Choice | By |
|---|---|---|
| Licence | **BSD 3-Clause** (as DSpace) | Lighton, November 4, 2026 |
| Where the manual is published (live since November 5, 2026: https://lightonphiri.github.io/code-datalab26-netd_aggregator/; GitHub releases for `v0.1.0`–`v0.9.0` created the same day) | Markdown in `docs/manual/` (master copy) **and** a static site built with MkDocs on GitHub Pages (`mkdocs.yml`, `.github/workflows/manual.yml`) | Lighton, November 4, 2026 |
| Milestone versions | Annotated tags `v0.1.0` to `v0.9.0` on the real milestone commits, tagged retrospectively; `paper-v1` unchanged; commit dates never rewritten | agreed November 4, 2026 |

**Licence file added (release P2, November 4, 2026):** Lighton confirmed that the University of Zambia's IP policy allows the open-source release (November 4, 2026); copyright line as prepared. *Earlier text:* Lighton checks the University of Zambia's intellectual property policy on software written by staff (who holds the copyright, and whether the University must approve an open-source release). The `LICENSE` text is prepared (section 6) and goes into the repository in the release after that check. Note that **the GitHub repository is already public** (checked November 4, 2026); without a licence file, others may read the code but have no right to reuse it.

## 2. Inventory: what is Zambian or installation-specific

Found with `grep` over `harvester/netd`, `portal/app`, `portal/config`, `portal/public`, `deploy`, `solr` and `tests` on November 4, 2026 (commit ae15b79). Counts are occurrences.

| Item | Where | Count | Target |
|---|---|---|---|
| Country name "Zambia", "Zambian" in text | 31 files: home page, footer, header wordmark, About, FAQ, Credits, Developer Resources, For Institutions, quality pages, browse, follow, admin sign-in, mailers, reports (Excel, PDF), OAI `Identify`, OpenAPI file, Blacklight locale, Apache comment | 62 | `country.name`, `portal.name` (with the two wordmark parts) in `config/country.yml`; text moved into locale files |
| Regulator ("HEA", "Higher Education Authority") | 17 files: home, footer, FAQ, developers, reports (`hea_report.rb`, controller, view), `User` (viewer role description), `InstitutionRegistry`, `Harvester`, CSV upload, API institutions, MIME types, routes comment | 23 | `regulator.name`, `regulator.short_name`, `regulator.register_url`; rename `HeaReport` to `EtdReport` (class only; reports unchanged) |
| Host name `netd.ac.zm` | 25 files: Apache sites, `deploy.sh`, probe script and unit, alert script, upgrade check, `production.rb` (mailer host), `robots.txt`, `openapi.yaml`, OAI controller (identifier namespace), API base controller, `ApiRecord`, reports, developers page, harvester user agents (`csvload.py`, `repocheck.py`, `textcache.py`), `evaluate.py` (gold sample links), tests | 57 | `portal.host` in `country.yml`; read by Rails (`Rails.configuration.x.netd`), by Python (`netd.config`) and by the deployment scripts (one `deploy/site.env` written from `country.yml`); Apache sites rendered from templates |
| E-mail addresses (`datalab@unza.zm`, `lighton.phiri@unza.ac.zm`, `lighton.phiri@unza.zm`) | mailers (sender, recipients), footer, FAQ, contribute, developers, quality page, OAI `Identify` admin email, OpenAPI contact, Apache `ServerAdmin`, `netd-user.sh` example, backup script | 26 | `contact.email`, `contact.reports_to` (list), `mail.from` in `country.yml`; SMTP stays in `portal.env` |
| Developer and host credits (DataLab Research Group, ZAMREN) and their logos | header, footer, About, Credits, contribute, developers, FAQ, quality, `publications.yml`, OpenAPI, `netd.css`, `public/images/` | 65 | `credits` list in `country.yml` (name, URL, logo, role); the theme folder holds the logos |
| Institutions expected (HEA register) | `harvester/institutions.yml` | 34 entries | stays a file per installation; shipped as `config/examples/zambia/institutions.yml` |
| Sources | `harvester/sources.yml` | 4 sources | the same: Zambia as the example; a demo source (section 4) as the default |
| Publications on the About page | `portal/config/publications.yml`, `PUBLICATIONS.md` | — | installation file; Zambia as the example |
| Time zone `Africa/Lusaka` | `admin_helper.rb` (admin times), `geo_lookup.rb`, `netd-weekly.timer` comment, quality and usage pages ("Lusaka time") | 10 | `country.time_zone`; `config.time_zone` set from it; labels from it |
| Place names kept capitalised in citations | `KEEP` in `portal/app/models/citation.rb` (Zambia, Lusaka, Copperbelt, provinces…) | 1 list | `citation.keep_capitals` in `country.yml`, merged with a generic list (Africa, continents) |
| Words never taken as names (title-page rules) | `NOT_NAMES` and the title-word list in `harvester/netd/ml/models/titlepage.py` (`unza`, `zou`, `cbu`, `unilus`, `zcas`, `mu`, `zambia`) | 2 | built at start-up from the `short_name`s in `sources.yml`/`institutions.yml` and `country.name`; **a model change: new `VERSION`, evaluated, post-paper evidence row** |
| Record id rule for UNZA handles; UNZA-specific comments | `crosswalk.py` (comments and examples only) | 3 | none (generic code; comments may stay) |
| UNZA-specific degree text patterns | `crosswalk.py` "Master of Education in …" | — | generic English patterns; documented as such in manual chapter 9 |
| Data protection wording | FAQ (usage counting, log retention); none mentions the Data Protection Act by name in code | 0 | `privacy` page text per installation (locale file), with the country's law named there |
| Off-server backup destination | `netd-backup-to-gdrive.sh` (`REMOTES`, Drive folder "NETD portal backups") | — | `backup.remotes` in `deploy/site.env`; empty means server-only backups |
| Search Console verification file | `portal/public/google3d6feb9cbe4a8169.html` | 1 | installation file: kept for Zambia, documented as such; not shipped in a neutral build (moved to the Zambian example's `public/` overlay) |
| Old-portal redirects and other applications' paths | `deploy/apache/netd-le-ssl.conf` (`/portal`, `/summary`, `/harvester`, `/beta`, `/znrp`, `/ojs`) | — | Zambian example only; the template has a single `ProxyPass /` |
| Colours and wordmark | `netd.css` variables, header component | — | theme folder (`themes/<name>/`: `theme.css` with the variables, logos, wordmark) |
| Interface language | most text written in templates; 6 files use `t()` | — | text moved to `config/locales/en.yml` keys; one locale file per language |
| Operations runbook | `docs/OPERATIONS.md` | — | stays the Zambian installation's own runbook; the manual is the generic text |

## 3. Target: one country configuration

```text
config/
  country.yml                    # the installation's identity (below); copied from an example
  examples/
    zambia/   country.yml, institutions.yml, sources.yml, publications.yml, public/ (verification file), theme
    demo/     country.yml, institutions.yml, sources.yml (one public demo source)
themes/
  default/   theme.css, logo.svg, wordmark
  zambia/    theme.css, logos (DataLab, ZAMREN)
portal/config/locales/  en.yml (all interface text), blacklight.en.yml
```

```yaml
# config/country.yml (sketch; Zambia as the shipped example)
country:   {name: Zambia, adjective: Zambian, time_zone: Africa/Lusaka}
portal:    {name: Zambia National ETD Portal, wordmark: [Zambia, National ETD Portal], host: netd.ac.zm, theme: zambia}
regulator: {name: Higher Education Authority, short_name: HEA, register_url: https://online.hea.org.zm}
contact:   {email: datalab@unza.zm, reports_to: [lighton.phiri@unza.ac.zm, datalab@unza.zm]}
mail:      {from: lighton.phiri@unza.ac.zm}
credits:
  - {name: DataLab Research Group, url: https://datalab.unza.zm, logo: datalab-logo-light.svg, role: developed by}
  - {name: ZAMREN, url: https://zamren.zm, logo: zamren-logo.png, role: hosted by}
citation:  {keep_capitals: [Zambia, Zambian, Lusaka, Copperbelt, Luapula]}
locale:    en
```

Loaded once at start-up: Rails (`config/initializers/netd_country.rb` → `Rails.configuration.x.country`), the harvester (`netd/config.py`, `NETD_COUNTRY` to override the path), and the deployment scripts (`deploy/site.env`, written by `deploy.sh` from `country.yml`). A missing or invalid file stops start-up with a clear message. The current paths and the Zambian installation's behaviour stay the same: Zambia's `country.yml` reproduces today's text exactly (checked page by page with screenshots before and after).

## 4. Steps (small releases, each post-paper)

**P3 in two parts.** P3a (November 4, 2026): `config/country.yml`, the loaders and `deploy/site.env`; host name, contacts, senders, portal name in mail, reports and OAI-PMH, time zone. P3b (November 5, 2026): country and regulator names, wordmark and credits in page text, citation `KEEP` list; accepted by the scratch-copy boot test (22 responses compared) and identical captures before and after. `HeaReport` keeps its name (invisible to users; renaming would touch the maintenance track's report code). Static files and Apache sites stay for P6.

| # | Release | Contents | Check |
|---|---|---|---|
| P1 | Repository hygiene | remove the tracked `deploy/ops/__pycache__/*.pyc`; `.gitignore` for all `__pycache__` and `site/`; `CHANGELOG.md`; manual; MkDocs and Pages workflow | `git ls-files` has no caches; the manual builds with `mkdocs build --strict` |
| P2 (done November 4, 2026) | Licence and notices | `LICENSE` (BSD 3-Clause), `NOTICE` (section 6), `CONTRIBUTING.md`, `SECURITY.md` (how to report a vulnerability), README licence section | after Lighton's IP policy check |
| P3 (P3a done November 4, 2026; P3b done November 5, 2026) | Country configuration, read-only | `country.yml` and the loaders; replace host name, contacts, time zone and names in code with configuration reads; Zambia's file reproduces today's pages | page-by-page screenshots identical; API and OAI conformance tests pass |
| P4 | Text into locale files | template text into `en.yml` keys | screenshots identical |
| P5 | Theme folder | `themes/default` (neutral colours, generic wordmark) and `themes/zambia` | screenshots with each theme |
| P6 | Deployment templates | Apache sites, probe, alert and backup scripts rendered from `deploy/site.env`; `install-server.sh` also installs uv and checks Java; no Zambian paths left in `deploy/` | a fresh install on a clean VM following manual chapter 3 |
| P7 | Demo data and source | `config/examples/demo/`: a small public OAI-PMH source (or a bundled sample of public records as CSV) so a new installation shows results at once | fresh install shows records after `netd.cli run` |
| P8 | Container installer | Docker Compose with Solr, the portal and the harvester (cron in a container or a scheduler service), volumes for the stores, `.env` for secrets; for installations that do not share a server (the native install stays for shared servers such as Zambia's) | `docker compose up` on a clean VM, then the conformance tests |
| P9 | Title-page rules without Zambian words | `NOT_NAMES` built from configuration | **model change**: new `VERSION`, dev-half tuning only, `evaluate --strata` on both halves, new post-paper evidence row in `docs/PAPER-PLAN.md`; FINAL rows untouched |
| P10 | First open-source release | `v1.0.0` tag, GitHub release with the CHANGELOG text, announcement | manual site live; a second person installs from the manual alone |

Every code change follows the usual rules: SRS and SDD updated, `CHANGELOG.md` under `[Unreleased]`, small releases, rule 28 (check that the maintenance track has not released since the copy was taken).

## 5. Security check of the public repository

The repository is already public, so this check came first (November 4, 2026, on the full history of all branches):

| Check | Result |
|---|---|
| Files ever committed with risky names (`.env`, keys, `master.key`, rclone, OAuth, SQLite stores, gold or annotation files, credentials) | none, apart from `portal/config/credentials.yml.enc`, which is encrypted and useless without `master.key` (never committed; ignored). The portal reads its secrets from `portal.env`, so the encrypted file can be dropped from the public release |
| Private keys, GitHub tokens, Google API keys or OAuth client secrets in any committed text | none found |
| `SMTP_PASSWORD=`, `SECRET_KEY_BASE=` with values | only placeholders (`the-16-character-app-password`) and the generator in `deploy.sh` |
| The NETD alert app password exposed on November 2, 2026 | it was pasted into a chat, not committed; it was revoked the same day |
| Server access files (`access/ssh.sh`, deploy key, `rclone-oauth.txt`) | outside the git working copy (`repo/`), and `access/` is ignored |
| Gold-standard annotations | not in the repository (they live on the server under `/opt/netd/logs/` and in the laptop's `work/` folder); keep it so |
| Personal data | names of authors and supervisors in examples and tests (public thesis metadata), the maintainers' work e-mail addresses (public contacts); IP addresses are never stored by the portal |

Leave out of the public repository, permanently: `access/`, `work/` (session scripts, gold sheets, usage logs), `portal.env`, rclone configuration, server backups, Apache access logs, `master.key`. Re-run the check before each release (`git log --all -p | grep -E 'BEGIN [A-Z ]*PRIVATE KEY|ghp_|AIza|GOCSPX-'`, and `git log --all --name-only --format=` over the risky names).

## 6. Licence and notices (prepared)

**`LICENSE`** (to add in release P2):

```text
BSD 3-Clause License

Copyright (c) 2026, Lighton Phiri and contributors

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

The copyright line depends on the IP policy check: it may have to name the University of Zambia as holder (for example "Copyright (c) 2026, University of Zambia (DataLab Research Group)"). Lighton decides after the check.

**`NOTICE`** (third-party material shipped in the repository or downloaded by the installer):

| Component | Licence | Where |
|---|---|---|
| CSL citation styles and the en-GB locale (Citation Style Language project) | CC BY-SA 3.0 | `portal/config/csl/` (authors in each file's `<info>`) |
| DB-IP Lite City database (IP to city) | CC BY 4.0, attribution "IP Geolocation by DB-IP" required where figures are shown | downloaded by `deploy/ops/geoip-update.sh`; not in the repository |
| OpenAlex taxonomy and works used to train `openalex-fos` | CC0 | `harvester/netd/ml/models/data/` |
| `sentence-transformers/all-MiniLM-L6-v2` (through fastembed) | Apache 2.0 | downloaded at first use |
| Blacklight | Apache 2.0 | Ruby gem |
| Ruby on Rails, Puma, Prawn and prawn-table, caxlsx, citeproc-ruby, csl, bcrypt, maxmind-db, rsolr | MIT, BSD or Ruby licence (each gem's own file) | Ruby gems |
| Apache Solr | Apache 2.0 | downloaded by `install-server.sh` |
| Sickle | BSD 3-Clause | Python package |
| lxml, PyYAML, pypdf, fastembed | BSD, MIT, BSD, Apache 2.0 | Python packages |
| Tesseract OCR | Apache 2.0 | Ubuntu package |
| Swagger UI (API reference page) | Apache 2.0 | loaded on `/developers/api` |

Check each dependency's licence file once more when `NOTICE` is written (P2), from `Gemfile.lock` and the Python requirements.
