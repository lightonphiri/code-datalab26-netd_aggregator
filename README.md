# NETD v2 — Zambia National ETD Aggregator

Harvests Electronic Theses and Dissertations (ETD) metadata from Zambian institutional repositories over OAI-PMH, cleans it (rules plus pluggable ML models, with per-field provenance), and serves faceted discovery with Blacklight 9 and Solr.

- **Live:** https://netd.ac.zm/ (replaced the earlier UCT ETD Portal deployment on October 31, 2026)
- **Requirements:** [docs/SRS.md](docs/SRS.md) (ISO/IEC/IEEE 29148)
- **Design:** [docs/SDD.md](docs/SDD.md) (IEEE 1016, with UML)
- **Project page:** https://datalab.unza.zm/projects/zambia-national-etd-portal
- **Publications based on the project:** [PUBLICATIONS.md](PUBLICATIONS.md) (also on the portal's About page)
- **Maintainer:** DataLab Research Group

### Document versioning
The SRS and SDD are kept in two places, changed together on every release:
- `docs/SRS.md` and `docs/SDD.md` here: full history in git.
- Google Docs working copies ([SRS](https://docs.google.com/document/d/1rGBlOvs6cJsIqVdYAZG1lUyff2j0-QYRwmqODysBhPM/edit), [SDD](https://docs.google.com/document/d/12g3y1FZUcVuRKnmhpchIZglu1xEXX8pPo3x2XOJ0Rno/edit)), updated with targeted edits so Google's version history records each change.

Each document starts with a revision history giving the version, date and changes.

## Layout
| Path | What |
|---|---|
| `harvester/` | Python package `netd`: harvest → raw store → crosswalk + enrichers → canonical records → Solr |
| `harvester/sources.yml` | Source registry (one entry per HEI) |
| `harvester/enrichers.yml` | Where ML models are plugged in |
| `portal/` | Rails 8 + Blacklight 9 discovery interface |
| `solr/netd/conf` | Solr configset (Blacklight schema, ETD search fields) |
| `deploy/` | Server install/deploy scripts, systemd units, Apache snippet |

## Run the harvester locally
```bash
cd harvester
python3 -m venv .venv && . .venv/bin/activate      # Python 3.8+
pip install -r requirements.txt
python -m netd.cli harvest --source unza --full --limit 50
python -m netd.cli process
python -m netd.cli report
# with a Solr core at http://127.0.0.1:8983/solr/netd:
python -m netd.cli index
```

## Run the portal locally
```bash
cd portal
bundle install                                      # Ruby 3.3
SOLR_URL=http://127.0.0.1:8983/solr/netd bin/rails server
```

## Add a repository
Add an entry to `harvester/sources.yml`: `id`, `name`, `short_name`, `base_url`, the ETD `sets` (find them with `?verb=ListSets`), and optionally `collections_are: faculty|department`. Then run `python -m netd.cli run --source <id> --full`.

## Plug in an ML model
Write `def enrich(record) -> record` in any importable package. Set `record["provenance"][field] = "model:<name>-<version>"`, and optionally `record["confidence"][field]`. Register it in `harvester/enrichers.yml`, then run `netd.cli process` and `netd.cli index`. See `harvester/netd/enrich.py`.

## Server deployment (netd.ac.zm)
```bash
sudo bash /opt/netd/deploy/install-server.sh   # once: swap, Solr 9, Ruby 3.3 (no Docker, no apt)
sudo bash /opt/netd/deploy/deploy.sh           # each release: core, gems, assets, systemd, Apache sites
sudo -u netd /opt/netd/harvester/.venv/bin/python -m netd.cli run --full   # first load
```
Apache sites for netd.ac.zm are kept in `deploy/apache/` and installed by `deploy.sh` (the previous files are backed up in `/opt/netd/*.bak-*`). The old Tomcat ETD Portal addresses (`/portal`, `/summary`, `/harvester`) redirect to the home page; `/beta/...` redirects to the same path at the root.

### HTTPS
netd.ac.zm has a Let's Encrypt certificate (obtained on October 30, 2026 with `certbot certonly --webroot -w /var/www/html -d netd.ac.zm`; it renews automatically and Apache reloads via the deploy hook). The HTTPS site `/etc/apache2/sites-available/netd-le-ssl.conf` proxies the whole site to the portal, plus `RequestHeader set X-Forwarded-Proto "https"` (mod_headers) so Rails knows requests arrived over HTTPS; without it, clicking a search result fails Rails' CSRF origin check (fixed October 31, 2026).

### Problem reports (record page form)
Reports are stored in the portal database and emailed to lighton.phiri@unza.ac.zm and datalab@unza.zm once SMTP is configured.
To enable email, create a Google app password for the sending account (Google Account → Security → 2-Step Verification → App passwords), then on the server:
```bash
sudo tee -a /opt/netd/portal.env >/dev/null <<'ENV'
SMTP_USER=datalab@unza.zm
SMTP_PASSWORD=the-16-character-app-password
ENV
sudo systemctl restart netd-portal
```
List reports: `cd /opt/netd/portal && sudo -u netd env PATH=/opt/netd/ruby/bin:$PATH RAILS_ENV=production $(sudo cat /opt/netd/portal.env) bin/rails netd:reports`
