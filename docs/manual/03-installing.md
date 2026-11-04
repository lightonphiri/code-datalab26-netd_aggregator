# 3. Installing

This chapter installs NETD on a clean Ubuntu server. It follows what the scripts in `deploy/` do on the Zambian server; where those scripts still contain the Zambian host name, the step says what to change. A container-based installer that does not assume a particular server is planned (see `docs/PACKAGING-PLAN.md`).

## 3.1 Prerequisites

| Item | Requirement | Notes |
|---|---|---|
| Server | Ubuntu Server 24.04 or 26.04 LTS, 2 vCPU, 4 GB RAM, 20 GB free disk | The Zambian installation runs on 3.8 GB RAM shared with other services; `install-server.sh` adds 2 GB of swap |
| Domain name | A host name pointing at the server, ports 80 and 443 open | Needed for HTTPS (Let's Encrypt) |
| Java | OpenJDK 11 or later (`openjdk-21-jre-headless`) | For Solr 9 |
| Build tools | `build-essential git curl libssl-dev libyaml-dev zlib1g-dev libffi-dev libreadline-dev libsqlite3-dev sqlite3` | Ruby is compiled once with ruby-build |
| Web server | Apache 2.4 with `mod_proxy`, `mod_proxy_http`, `mod_headers`, `mod_rewrite`, `mod_ssl`; `certbot` and `python3-certbot-apache` | Apache terminates TLS and proxies to the portal |
| OCR | `tesseract-ocr tesseract-ocr-eng poppler-utils` | For scanned theses (metadata filling) |
| Python | installed by `uv` (Python 3.12) | No system Python packages are used |
| Ruby | 3.3.6, compiled by `install-server.sh` | No system Ruby is used |
| Solr | 9.11 slim distribution, installed by `install-server.sh` | Bound to 127.0.0.1:8983 |
| Mail | An SMTP account that may send (for alerts and problem reports) | Optional at first; alerts are not sent without it |

```bash
sudo apt-get update
sudo apt-get install -y build-essential git curl sqlite3 libsqlite3-dev libssl-dev libyaml-dev zlib1g-dev \
  libffi-dev libreadline-dev openjdk-21-jre-headless apache2 certbot python3-certbot-apache \
  tesseract-ocr tesseract-ocr-eng poppler-utils
```

## 3.2 Service user and code

Everything runs as the unprivileged user `netd` under `/opt/netd`. The repository's top-level folders (`harvester/`, `portal/`, `solr/`, `deploy/`) sit directly in `/opt/netd`.

```bash
sudo useradd --system --create-home --home-dir /opt/netd --shell /bin/bash netd
sudo -u netd git clone https://github.com/lightonphiri/code-datalab26-netd_aggregator.git /tmp/netd-src
sudo -u netd cp -a /tmp/netd-src/. /opt/netd/ && rm -rf /tmp/netd-src
cd /opt/netd && sudo -u netd git checkout v0.9.0      # or the latest release tag
```

Install `uv` where `deploy.sh` expects it:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sudo env UV_INSTALL_DIR=/opt/netd/bin UV_NO_MODIFY_PATH=1 sh
sudo chown -R netd:netd /opt/netd/bin
```

## 3.3 Swap, Solr and Ruby

```bash
sudo bash /opt/netd/deploy/install-server.sh
```

This adds a 2 GB swap file, downloads Solr into `/opt/netd/solr-dist` (Solr home `/opt/netd/solr-home`), and compiles Ruby into `/opt/netd/ruby` (about 15 minutes on 2 vCPU). It is safe to run again: each step is skipped when already done. `RUBY_VERSION` and `SOLR_VERSION` can be set in the environment.

## 3.4 Site-specific files (before the first deployment)

Until the country configuration is in place, these files carry the Zambian installation's values. Change them for your host name, institutions and contacts (details in [chapter 7](07-configuration.md) and [chapter 8](08-customisation.md)):

| File | Change |
|---|---|
| `deploy/apache/netd.conf`, `deploy/apache/netd-le-ssl.conf` | `ServerName`, `ServerAlias`, `ServerAdmin`, certificate paths; remove the `ProxyPass … !` lines for other applications on the Zambian server (`/znrp`, `/ojs`) and the old-portal redirects if you do not need them |
| `deploy/ops/netd-probe.sh`, `deploy/systemd/netd-probe.service`, `deploy/ops/netd-alert.py` | the public address checked and named in alerts |
| `portal/config/environments/production.rb` | `action_mailer.default_url_options` host |
| `harvester/sources.yml` | your repositories (one entry each) |
| `harvester/institutions.yml` | every institution expected to contribute, with status |
| `portal/app/mailers/*.rb` | sender and recipients of problem reports |
| `deploy/ops/netd-backup-to-gdrive.sh` | rclone remote and Drive folder for off-server backups (or disable the Drive copy) |

## 3.5 Deploy

```bash
sudo bash /opt/netd/deploy/deploy.sh
```

`deploy.sh` creates the Solr core `netd` from `solr/netd/conf`, creates the harvester's Python environment, writes `/opt/netd/portal.env` with a new `SECRET_KEY_BASE` if it does not exist, installs the portal's gems, prepares the portal database, precompiles assets, downloads the offline place database for usage figures, installs rclone, installs and starts the systemd units, and installs the Apache sites (backing up any existing ones in `/opt/netd/*.bak-*`). Run it again after every code update.

## 3.6 HTTPS

```bash
sudo certbot certonly --webroot -w /var/www/html -d your.host.name
sudo systemctl reload apache2
```

Certificates renew automatically. The HTTPS site must send `RequestHeader set X-Forwarded-Proto "https"` (it does in `deploy/apache/netd-le-ssl.conf`); without it, Rails rejects form posts from the record pages.

## 3.7 Mail (optional, recommended)

Add the sending account to `/opt/netd/portal.env` (mode 600, owner `netd`), then restart the portal:

```bash
sudo -u netd tee -a /opt/netd/portal.env >/dev/null <<'ENV'
SMTP_ADDRESS=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=sender@your.institution
SMTP_PASSWORD=app-password-for-this-service
ALERT_TO=team@your.institution
ENV
sudo systemctl restart netd-portal
sudo systemctl start netd-alert@test.service     # sends a test alert
```

Use one app password per service, so that one can be revoked without breaking the others.

## 3.8 First harvest

```bash
cd /opt/netd/harvester
sudo -u netd flock -w 7200 run.lock .venv/bin/python -m netd.cli run --full
sudo -u netd .venv/bin/python -m netd.cli report
sudo -u netd .venv/bin/python -m netd.cli check
```

`run` harvests, processes and indexes every source. A first harvest of 5,000 records takes about 15 minutes, mostly waiting for the repositories. To try one source with a few records first: `netd.cli harvest --source <id> --full --limit 50`, then `process` and `index`.

Metadata filling (PDF text, OCR, predictions) then runs a little every night (`ml.nightly` in `enrichers.yml`); for a large backlog see [chapter 9](09-metadata-filling.md).

## 3.9 First administrator

```bash
sudo bash /opt/netd/deploy/ops/netd-user.sh add EMAIL=you@your.institution NAME="Your Name"
```

The command prints a one-time password; the account must change it at first sign-in at `/admin`.

## 3.10 Checking the installation

| Check | Expected |
|---|---|
| `systemctl status netd-solr netd-portal` | both active |
| `curl -s http://127.0.0.1:3010/up` | HTTP 200 |
| `curl -s 'https://your.host.name/oai?verb=Identify'` | an OAI-PMH `Identify` response |
| `curl -s https://your.host.name/api/v1/stats` | JSON with record counts |
| `systemctl list-timers 'netd-*'` | harvest (daily), backup (daily), probe (every 15 minutes), weekly status |
| `sudo -u netd /opt/netd/harvester/.venv/bin/python -m netd.cli check` | `check: OK` |
| `sudo systemctl start netd-backup` then `tail /var/log/netd-backup.log` | a dated folder in `/var/backups/netd/` |

The conformance tests in `tests/` (see [chapter 12](12-developing.md)) check the OAI-PMH provider and the REST API against their specifications.
