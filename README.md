# NETD v2 — Zambia National ETD Aggregator

Harvests Electronic Theses and Dissertations (ETD) metadata from Zambian institutional repositories over OAI-PMH, cleans it (rules plus pluggable ML models, with per-field provenance), and serves faceted discovery with Blacklight 9 and Solr.

- **Beta:** https://netd.ac.zm/beta/ (runs alongside the current portal)
- **Requirements:** [docs/SRS.md](docs/SRS.md) (ISO/IEC/IEEE 29148)
- **Design:** [docs/SDD.md](docs/SDD.md) (IEEE 1016, with UML)
- **Maintainer:** DataLab Research Group

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
sudo bash /opt/netd/deploy/deploy.sh           # each release: core, gems, assets, systemd, Apache /beta
sudo -u netd /opt/netd/harvester/.venv/bin/python -m netd.cli run --full   # first load
```
Roll back by deleting the "NETD v2 beta" lines in `/etc/apache2/sites-enabled/netd.conf` (a backup is kept in `/opt/netd/`), then `systemctl disable --now netd-portal netd-solr netd-harvest.timer`.

### HTTPS
netd.ac.zm has a Let's Encrypt certificate (obtained on October 30, 2026 with `certbot certonly --webroot -w /var/www/html -d netd.ac.zm`; it renews automatically and Apache reloads via the deploy hook). The HTTPS site `/etc/apache2/sites-available/netd-le-ssl.conf` mirrors `netd.conf`, including the `/beta` proxy.
