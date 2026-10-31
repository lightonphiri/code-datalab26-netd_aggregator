#!/bin/bash
# One-off server setup for NETD v2 (Ubuntu 20.04, no Docker, no apt changes).
# Installs under /opt/netd as user "netd": Ruby (ruby-build), Solr 9 (127.0.0.1:8983), swap file.
set -euo pipefail
RUBY_VERSION=${RUBY_VERSION:-3.3.6}
SOLR_VERSION=${SOLR_VERSION:-9.11.0}
N=/opt/netd

# 1. 2 GB swap file (safety net on a 4 GB server)
if ! swapon --show | grep -q /swapfile; then
  fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# 2. Solr (slim distribution), bound to localhost, 512 MB heap
# ($N/solr holds the project's Solr configset; the Solr software goes in $N/solr-dist)
if [ ! -x $N/solr-dist/bin/solr ]; then
  cd /tmp && [ -f solr-$SOLR_VERSION-slim.tgz ] || curl -fsSLO https://dlcdn.apache.org/solr/solr/$SOLR_VERSION/solr-$SOLR_VERSION-slim.tgz
  tar xzf solr-$SOLR_VERSION-slim.tgz -C $N && mv $N/solr-$SOLR_VERSION-slim $N/solr-dist
  mkdir -p $N/solr-home && cp $N/solr-dist/server/solr/solr.xml $N/solr-home/
  chown -R netd:netd $N/solr-dist $N/solr-home
fi

# 3. Ruby via ruby-build (compiled once; uses existing build libraries)
if [ ! -x $N/ruby/bin/ruby ]; then
  cd /tmp && rm -rf ruby-build && git clone -q --depth 1 https://github.com/rbenv/ruby-build.git
  MAKE_OPTS=-j2 ruby-build/bin/ruby-build $RUBY_VERSION $N/ruby
  chown -R netd:netd $N/ruby
fi
echo "install-server: done"
