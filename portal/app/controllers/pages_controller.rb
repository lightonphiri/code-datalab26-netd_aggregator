# frozen_string_literal: true

# Static "About" page: project details and linked publications (config/publications.yml).
class PagesController < ApplicationController
  include Blacklight::Configurable
  copy_blacklight_config_from(CatalogController)
  layout 'blacklight'

  def about
    @data = YAML.safe_load_file(Rails.root.join('config', 'publications.yml'))
  end
end
