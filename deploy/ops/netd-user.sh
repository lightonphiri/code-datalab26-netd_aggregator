#!/bin/bash
# Manage admin panel accounts (run as root on the server). See portal/lib/tasks/netd_users.rake.
#   netd-user.sh add EMAIL=jane@unza.zm NAME="Jane Banda" [ROLE=viewer] | role EMAIL=... ROLE=admin|viewer
#   | reset EMAIL=... | disable EMAIL=... | enable EMAIL=... | list
set -euo pipefail
N=/opt/netd
cmd=${1:?usage: netd-user.sh add|role|reset|disable|enable|list [EMAIL=...] [NAME=...] [ROLE=...]}; shift
cd $N/portal
exec sudo -u netd env PATH=$N/ruby/bin:$PATH RAILS_ENV=production $(cat $N/portal.env) "$@" bin/rails "netd:user:$cmd"
