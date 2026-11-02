#!/bin/bash
# Rebuild NETD's Ruby against the current system libraries (after an Ubuntu release upgrade; November 2, 2026).
# Builds in place (the old build is kept as ruby-<release>-before-rebuild and restored if the build fails),
# then rebuilds the portal's native gem extensions. Run as root: bash rebuild-ruby.sh
set -Eeuo pipefail
N=/opt/netd; V=$($N/ruby/bin/ruby -e 'print RUBY_VERSION' 2>/dev/null || echo 3.3.6)
OLD=ruby-$(sed -n 's/^VERSION_CODENAME=//p' /etc/os-release)-before-rebuild
log() { echo "$(date -u +%H:%M:%S) $*"; }
export DEBIAN_FRONTEND=noninteractive
apt-get install -y -q build-essential autoconf libssl-dev libyaml-dev libffi-dev zlib1g-dev libreadline-dev libgdbm-dev libgmp-dev git >/dev/null
log "building Ruby $V in place (Ruby records its prefix; the portal is down during the build, about 5 minutes)"
cd /tmp && rm -rf ruby-build && git clone -q --depth 1 https://github.com/rbenv/ruby-build.git
systemctl stop netd-portal
rm -rf $N/$OLD; mv $N/ruby $N/$OLD
trap 'echo "build failed: restoring the old Ruby"; rm -rf $N/ruby; mv $N/$OLD $N/ruby; systemctl start netd-portal' ERR
MAKE_OPTS=-j2 ruby-build/bin/ruby-build "$V" $N/ruby
$N/ruby/bin/ruby -ropenssl -e 'puts OpenSSL::OPENSSL_LIBRARY_VERSION'
B=$(awk '/^BUNDLED WITH/{getline; print $1}' $N/portal/Gemfile.lock)
[ -n "$B" ] && $N/ruby/bin/gem install -q --no-document bundler -v "$B"
chown -R netd:netd $N/ruby
log "rebuilding the portal's native gem extensions (old Ruby kept as $N/$OLD)"
cd $N/portal
sudo -u netd env PATH=$N/ruby/bin:/usr/bin:/bin bash -c 'bundle config set --local deployment true && bundle config set --local without development:test && bundle pristine >/dev/null && bundle install -j2 --quiet'
rm -f /etc/systemd/system/netd-portal.service.d/compat-focal.conf; rmdir /etc/systemd/system/netd-portal.service.d 2>/dev/null || true
systemctl daemon-reload; systemctl start netd-portal; sleep 20
systemctl is-active netd-portal
missing=$(find $N/ruby $N/portal/vendor -name '*.so' -exec ldd {} \; 2>/dev/null | grep -c 'not found' || true)
log "libraries not found after rebuild: $missing"
curl -s -o /dev/null -w 'portal %{http_code}\n' http://127.0.0.1:3010/
log "RUBY REBUILD DONE"
