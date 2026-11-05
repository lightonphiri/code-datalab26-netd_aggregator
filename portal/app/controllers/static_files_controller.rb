# frozen_string_literal: true

# Files that name the installation, rendered from config/country.yml (packaging P6a; SRS NFR-15, SDD 8.1). Until P6a they
# were static files in portal/public, which is served before the routes: robots.txt (the sitemap address) and the REST API
# specification (portal name, addresses, contact). Not an ApplicationController: no layout, no usage counting, as before.
class StaticFilesController < ActionController::Base
  def robots = render_file('robots', 'text/plain')

  def openapi
    @contact_name = Netd.credit('developed by')&.dig('name') || Netd.portal_name
    @contact_url = YAML.safe_load_file(Rails.root.join('config', 'publications.yml')).dig('project', 'url') || Netd.base_url
    render_file('openapi', 'text/yaml')
  end

  private

  def render_file(name, type)
    expires_in 1.day, public: true
    render template: "static_files/#{name}", formats: [:text], layout: false, content_type: type
  end
end
