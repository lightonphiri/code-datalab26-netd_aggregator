# frozen_string_literal: true

# robots.txt and the REST API specification are rendered from config/country.yml since packaging P6a
# (StaticFilesController, app/views/static_files/). A copy left in portal/public would be served first, with another
# installation's addresses: warn at start-up (the journal of netd-portal.service shows it).
%w[robots.txt api/v1/openapi.yaml].each do |f|
  next unless File.exist?(Rails.public_path.join(f))

  warn "NETD: portal/public/#{f} shadows the rendered file (app/views/static_files/); remove it (packaging P6a)"
end
