#!/bin/bash
# (Re)deploy NETD v2 (https://netd.ac.zm/) on the server from /opt/netd (run as root after syncing the code).
set -euo pipefail
N=/opt/netd
mkdir -p $N/logs/solr $N/harvester/uploads && chown -R netd:netd $N/logs $N/harvester/uploads

# Solr core "netd" from the project's configset (core discovery)
mkdir -p $N/solr-home/netd && rm -rf $N/solr-home/netd/conf && cp -r $N/solr/netd/conf $N/solr-home/netd/conf
[ -f $N/solr-home/netd/core.properties ] || echo "name=netd" > $N/solr-home/netd/core.properties
chown -R netd:netd $N/solr-home

# Harvester environment
cd $N/harvester && sudo -u netd $N/bin/uv venv -q --allow-existing --python 3.12 .venv && \
  sudo -u netd $N/bin/uv pip install -q --python .venv/bin/python -r requirements.txt

# Portal: gems, secrets, database, assets
[ -f $N/portal.env ] || { echo "SECRET_KEY_BASE=$(head -c 64 /dev/urandom | od -An -tx1 | tr -d ' \n')" > $N/portal.env; chmod 600 $N/portal.env; chown netd:netd $N/portal.env; }
cd $N/portal
sudo -u netd env PATH=$N/ruby/bin:$PATH bash -c 'bundle config set --local deployment true && bundle config set --local without development:test && bundle install -j2 --quiet'
sudo -u netd env PATH=$N/ruby/bin:$PATH RAILS_ENV=production RAILS_RELATIVE_URL_ROOT=/ $(cat $N/portal.env) bash -c 'bin/rails db:prepare && bin/rails assets:precompile' >/dev/null

# Operations: backup/alert scripts, rclone for the off-server copy (docs/OPERATIONS.md)
chmod 755 $N/deploy/ops/*
command -v rclone >/dev/null || { curl -sSf https://rclone.org/install.sh | bash >/dev/null; }

# systemd units
cp $N/deploy/systemd/netd-* /etc/systemd/system/ && systemctl daemon-reload
systemctl enable -q --now netd-solr.service netd-harvest.timer netd-backup.timer netd-probe.timer netd-weekly.timer
sleep 3; curl -s -o /dev/null "http://127.0.0.1:8983/solr/admin/cores?action=RELOAD&core=netd" || true  # pick up configset changes
systemctl restart netd-portal.service; systemctl enable -q netd-portal.service

# Apache: install the netd.ac.zm virtual hosts from deploy/apache (back up the live ones first)
for f in netd.conf netd-le-ssl.conf; do
  case $f in netd.conf) T=/etc/apache2/sites-enabled/netd.conf ;; *) T=/etc/apache2/sites-available/$f ;; esac
  if ! cmp -s $N/deploy/apache/$f $T; then
    [ -f $T ] && cp $T /opt/netd/$f.bak-$(date +%Y%m%d%H%M)
    cp $N/deploy/apache/$f $T; CHANGED=1
  fi
done
if [ "${CHANGED:-}" = 1 ]; then
  a2enmod -q headers rewrite proxy proxy_http >/dev/null; a2ensite -q netd-le-ssl >/dev/null
  apache2ctl configtest && systemctl restart apache2
fi
echo "deploy: done"
