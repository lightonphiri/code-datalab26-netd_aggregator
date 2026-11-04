# 4. Upgrading

## 4.1 Upgrading to a new release

1. **Read the release notes** in `CHANGELOG.md` for every version between yours and the new one. Changes to `sources.yml`, `enrichers.yml` or the Solr configset are listed there.
2. **Back up** (the nightly backup is enough if it ran today):
   ```bash
   sudo systemctl start netd-backup && tail -3 /var/log/netd-backup.log
   ```
3. **Stop the timers** so that no harvest starts during the upgrade:
   ```bash
   sudo systemctl stop netd-harvest.timer netd-probe.timer
   ```
4. **Get the code** and keep your site-specific changes (commit them on a local branch, or keep them in files that the release does not touch, such as `harvester/sources.local.yml`):
   ```bash
   cd /opt/netd && sudo -u netd git fetch --tags && sudo -u netd git checkout vX.Y.Z
   ```
5. **Deploy:** `sudo bash /opt/netd/deploy/deploy.sh` (gems, database migrations, assets, Solr configset reload, systemd units, Apache sites).
6. **Rebuild derived data when the release notes say so:**
   - crosswalk, rules, exclusions or thresholds changed → `netd.cli reprocess` (process and index every source without harvesting, about 30 seconds per 5,000 records);
   - Solr schema changed → `netd.cli index`;
   - a model changed → `netd.cli predict`, then `reprocess` (see [chapter 9](09-metadata-filling.md); the guarded script `deploy/ops/netd-ml-apply.sh` does both safely).
   Commands that write the store run under the harvest lock: `sudo -u netd flock -w 7200 run.lock .venv/bin/python -m netd.cli reprocess` in `/opt/netd/harvester`.
7. **Start the timers and check:**
   ```bash
   sudo systemctl start netd-harvest.timer netd-probe.timer
   sudo -u netd /opt/netd/harvester/.venv/bin/python -m netd.cli check
   ```

**Rollback:** check out the previous tag and run `deploy.sh` again. A restore of the staging store is only needed if the new release changed stored data; the backup's `MANIFEST.txt` gives the counts to compare.

## 4.2 Upgrading the operating system

NETD uses its own Ruby (compiled), its own Python (uv) and Solr's own distribution, so an Ubuntu release upgrade affects it mainly through the system libraries Ruby was linked against (OpenSSL, libffi). The scripts in `deploy/ops/upgrade/` were written for the Zambian server's upgrade from 20.04 to 26.04 (November 2, 2026); the NETD-relevant ones are general:

| Script | Use |
|---|---|
| `upgrade-backup.sh` | full server backup before the upgrade (consistent SQLite copies, configuration, `/opt`), copied off the server and verified |
| `upgrade-check.sh` | after each release hop: services, a list of URLs, versions, `netd.cli check`; writes a dated report |
| `rebuild-ruby.sh` | rebuilds NETD's Ruby in place against the new system libraries and rebuilds native gem extensions; restores the old build if it fails |
| `compat-focal.sh` | only for keeping binaries built on an older release running during the upgrade (shared servers) |

Checklist:

1. Stop the NETD timers and any long-running OCR unit; timers restart after each reboot, so stop them again until the upgrade is finished.
2. Run `upgrade-backup.sh` and check the copy.
3. For each hop: `apt-get -s full-upgrade` (read what would be removed), `full-upgrade`, `do-release-upgrade`, reboot, `upgrade-check.sh`.
4. After the last hop: `rebuild-ruby.sh`; recreate the harvester environment (`deploy.sh` does this with uv); run `deploy.sh`; `netd.cli check`.
5. **Never run `apt-get autoremove` without simulating it first** (`apt-get -s autoremove`): after a release upgrade it may list packages other services need.
6. Start the timers again.

The Zambian installation's full account of its upgrade, including what broke on the shared server, is in `docs/OPERATIONS.md`, "Ubuntu upgrade 20.04 → 22.04 → 24.04 → 26.04".
