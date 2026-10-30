#!/bin/bash
# (Re)deploy NETD v2 beta on the server from /opt/netd (run as root after syncing the code).
set -euo pipefail
N=/opt/netd
mkdir -p $N/logs/solr && chown -R netd:netd $N/logs

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
sudo -u netd env PATH=$N/ruby/bin:$PATH RAILS_ENV=production RAILS_RELATIVE_URL_ROOT=/beta $(cat $N/portal.env) bash -c 'bin/rails db:prepare && bin/rails assets:precompile' >/dev/null

# systemd units
cp $N/deploy/systemd/netd-* /etc/systemd/system/ && systemctl daemon-reload
systemctl enable -q --now netd-solr.service netd-harvest.timer
systemctl restart netd-portal.service; systemctl enable -q netd-portal.service

# Apache: add /beta proxy to the netd.ac.zm vhost once
C=/etc/apache2/sites-enabled/netd.conf
if ! grep -q "NETD v2 beta" $C; then
  cp $C /opt/netd/netd.conf.bak-$(date +%Y%m%d%H%M)
  sed -i "/ProxyPass \/portal /e cat $N/deploy/apache-netd-beta.conf" $C
  apache2ctl configtest && systemctl reload apache2
fi
echo "deploy: done"
