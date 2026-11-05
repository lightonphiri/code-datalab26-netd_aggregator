# frozen_string_literal: true

# The installation's theme (packaging P5; SDD 8.1, manual 8.2): themes/<portal.theme>/stylesheets is an asset path
# (application.css imports its theme.css last), and themes/<portal.theme>/public is served like portal/public, after it.
dir = Netd.theme_dir
unless File.file?(File.join(dir, 'stylesheets', 'theme.css'))
  raise "NETD: theme #{Netd.theme.inspect} not found (#{dir}/stylesheets/theme.css); set portal.theme in config/country.yml"
end

Rails.application.config.assets.paths << File.join(dir, 'stylesheets')
if Rails.application.config.public_file_server.enabled && File.directory?(File.join(dir, 'public'))
  Rails.application.config.middleware.insert_after ActionDispatch::Static, ActionDispatch::Static, File.join(dir, 'public'),
                                                   headers: Rails.application.config.public_file_server.headers || {}
end
