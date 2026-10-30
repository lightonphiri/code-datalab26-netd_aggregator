# This file is used by Rack-based servers to start the application.
require_relative "config/environment"

# Served under a sub-path (e.g. /beta) when RAILS_RELATIVE_URL_ROOT is set.
map ENV.fetch("RAILS_RELATIVE_URL_ROOT", "/") do
  run Rails.application
end
Rails.application.load_server
